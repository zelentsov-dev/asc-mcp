import Foundation
import MCP

// MARK: - Tool Handlers
extension AppLifecycleWorker {

    private func versionFilterValues(
        _ name: String,
        from arguments: [String: Value],
        allowedValues: Set<String>? = nil
    ) throws -> [String]? {
        guard let value = arguments[name] else {
            return nil
        }
        guard let items = value.arrayValue, !items.isEmpty else {
            throw AppLifecycleQueryArgumentError("\(name) must be a non-empty array of strings")
        }
        let strings = try items.map { item in
            guard let string = item.stringValue,
                  string == string.trimmingCharacters(in: .whitespacesAndNewlines),
                  !string.isEmpty else {
                throw AppLifecycleQueryArgumentError("\(name) must contain only non-empty strings")
            }
            return string
        }
        guard Set(strings).count == strings.count else {
            throw AppLifecycleQueryArgumentError("\(name) must not contain duplicate values")
        }
        if let allowedValues,
           let invalidValue = strings.first(where: { !allowedValues.contains($0) }) {
            throw AppLifecycleQueryArgumentError(
                "\(name) contains unsupported value '\(invalidValue)'; allowed values: \(allowedValues.sorted().joined(separator: ", "))"
            )
        }
        return strings
    }

    private func boundedInteger(
        _ name: String,
        from arguments: [String: Value],
        default defaultValue: Int,
        range: ClosedRange<Int>
    ) throws -> Int {
        guard let value = arguments[name] else {
            return defaultValue
        }
        guard let integer = value.intValue, range.contains(integer) else {
            throw AppLifecycleQueryArgumentError(
                "\(name) must be an integer from \(range.lowerBound) through \(range.upperBound)"
            )
        }
        return integer
    }

    /// Creates a new app version for release
    /// - Returns: JSON with created version details including ID, version string, platform and state
    /// - Throws: CallTool.Result with error if required parameters missing or API call fails
    func createVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue,
              let platform = arguments["platform"]?.stringValue,
              let versionString = arguments["version_string"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters missing: app_id, platform, version_string")],
                isError: true
            )
        }

        do {
            let releaseType = arguments["release_type"]?.stringValue ?? "MANUAL"
            let earliestDate = arguments["earliest_release_date"]?.stringValue
            let copyright = arguments["copyright"]?.stringValue
            let reviewType = arguments["review_type"]?.stringValue
            let usesIdfa = try nullableBool("uses_idfa", from: arguments)

            let request = CreateAppStoreVersionRequest(
                platform: platform,
                versionString: versionString,
                copyright: copyright,
                reviewType: reviewType,
                releaseType: releaseType,
                earliestReleaseDate: earliestDate,
                usesIdfa: usesIdfa,
                appId: appId
            )

            let requestBody = try JSONEncoder().encode(request)
            let responseData = try await httpClient.post("/v1/appStoreVersions", body: requestBody)
            let response: PassthroughAPIResponse
            do {
                response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)
                let createdVersion = try validatedJSONResource(
                    response.data,
                    expectedType: "appStoreVersions",
                    context: "app version create response"
                )
                _ = try validatedOptionalSingleRelationshipID(
                    createdVersion["relationships"],
                    name: "app",
                    expectedType: "apps",
                    expectedID: appId,
                    context: "created app version parent linkage"
                )
            } catch {
                return committedUnverifiedMutationFailure(
                    action: "app version creation",
                    reason: error.localizedDescription,
                    details: [
                        "app_id": appId,
                        "version_string": versionString,
                        "platform": platform,
                        "version_id_known": false
                    ],
                    inspection: [
                        "tool": "app_versions_list",
                        "arguments": [
                            "app_id": appId,
                            "version_strings": [versionString],
                            "platforms": [platform]
                        ]
                    ]
                )
            }

            let result: [String: Any] = [
                "success": true,
                "version": response.data.asAny,
                "message": "Version \(versionString) created successfully"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create version: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists all versions for an app with filtering options
    /// - Returns: JSON array of versions with their IDs, version strings, platforms and states
    /// - Throws: CallTool.Result with error if app_id missing or API call fails
    func listVersions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'app_id' is missing")
        }
        do {
            let appId = try requiredIdentifier("app_id", from: arguments)
            let effectiveLimit = try boundedInteger(
                "limit",
                from: arguments,
                default: 25,
                range: 1...200
            )
            let appStoreStates = try versionFilterValues(
                "states",
                from: arguments,
                allowedValues: Self.appStoreStates
            )
            let appVersionStates = try versionFilterValues(
                "app_version_states",
                from: arguments,
                allowedValues: Self.appVersionStates
            )
            let versionIDs = try versionFilterValues("version_ids", from: arguments)
            let versionStrings = try versionFilterValues("version_strings", from: arguments)
            let pluralPlatforms = try versionFilterValues(
                "platforms",
                from: arguments,
                allowedValues: Self.platforms
            )
            let legacyPlatform = try optionalIdentifier("platform", from: arguments)
            guard pluralPlatforms == nil || legacyPlatform == nil else {
                throw AppLifecycleQueryArgumentError("platform and platforms cannot be used together")
            }
            if let legacyPlatform, !Self.platforms.contains(legacyPlatform) {
                throw AppLifecycleQueryArgumentError(
                    "platform contains unsupported value '\(legacyPlatform)'; allowed values: \(Self.platforms.sorted().joined(separator: ", "))"
                )
            }

            var queryParameters: [String: String] = [
                "include": "build,appStoreVersionPhasedRelease",
                "limit": String(effectiveLimit)
            ]
            if let appStoreStates {
                queryParameters["filter[appStoreState]"] = appStoreStates.joined(separator: ",")
            }
            if let appVersionStates {
                queryParameters["filter[appVersionState]"] = appVersionStates.joined(separator: ",")
            }
            if let platforms = pluralPlatforms ?? legacyPlatform.map({ [$0] }) {
                queryParameters["filter[platform]"] = platforms.joined(separator: ",")
            }
            if let versionIDs {
                queryParameters["filter[id]"] = versionIDs.joined(separator: ",")
            }
            if let versionStrings {
                queryParameters["filter[versionString]"] = versionStrings.joined(separator: ",")
            }

            let responseData: Data
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                responseData = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(
                        path: "/v1/apps/\(try ASCPathSegment.encode(appId))/appStoreVersions",
                        query: queryParameters
                    )
                )
            } else {
                responseData = try await httpClient.get(
                    "/v1/apps/\(try ASCPathSegment.encode(appId))/appStoreVersions",
                    parameters: queryParameters
                )
            }

            let response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)
            let versions = try validatedJSONResourceCollection(
                response.data,
                expectedType: "appStoreVersions",
                context: "app version collection"
            )
            if let versionIDs {
                let requestedIDs = Set(versionIDs)
                for version in versions {
                    let versionObject = try validatedJSONResource(
                        version,
                        expectedType: "appStoreVersions",
                        context: "app version collection"
                    )
                    guard case .string(let returnedID)? = versionObject["id"],
                          requestedIDs.contains(returnedID) else {
                        throw AppLifecycleQueryArgumentError(
                            "Apple returned an app version outside the requested version_ids filter"
                        )
                    }
                }
            }
            try validateVersionIncludedResources(
                versions: versions,
                included: response.included,
                context: "app version collection"
            )

            var result: [String: Any] = [
                "success": true,
                "versions": response.data.asAny,
                "app_id": appId,
                "count": versions.count
            ]

            if case .object(let linksObj) = response.links,
               case .string(let nextUrl) = linksObj["next"] {
                result["next_url"] = nextUrl
            }

            if let included = response.included {
                result["included"] = included.map { $0.asAny }
            }
            if let meta = response.meta {
                result["meta"] = meta.asAny
                if let total = pagingTotal(from: meta) {
                    result["total"] = total
                }
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list versions: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets detailed information about a specific app version
    /// - Returns: JSON with complete version data including build info and metadata
    /// - Throws: CallTool.Result with error if version_id missing or API call fails
    func getVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionId = arguments["version_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            let queryParams: [String: String] = [
                "include": "build,appStoreVersionPhasedRelease"
            ]

            let response = try await httpClient.get(
                "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))",
                parameters: queryParams,
                as: PassthroughAPIResponse.self
            )
            _ = try validatedJSONResource(
                response.data,
                expectedType: "appStoreVersions",
                expectedID: versionId,
                context: "app version detail"
            )
            try validateVersionIncludedResources(
                versions: [response.data],
                included: response.included,
                context: "app version detail"
            )

            var result: [String: Any] = [
                "success": true,
                "version": response.data.asAny
            ]

            if let included = response.included {
                result["included"] = included.map(\.asAny)
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get version: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets the app-level age rating questionnaire for an App Info resource
    /// - Returns: JSON with the complete age rating declaration and selected App Info ID
    /// - Throws: CallTool.Result with error if app_info_id is missing or the API call fails
    func getAgeRatingDeclaration(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'app_info_id' is missing")
        }

        do {
            let appInfoId = try requiredIdentifier("app_info_id", from: arguments)
            let response = try await httpClient.get(
                "/v1/appInfos/\(try ASCPathSegment.encode(appInfoId))/ageRatingDeclaration",
                parameters: [:],
                as: PassthroughAPIResponse.self
            )
            _ = try validatedJSONResource(
                response.data,
                expectedType: "ageRatingDeclarations",
                context: "age rating declaration"
            )

            return MCPResult.jsonObject([
                "success": true,
                "app_info_id": appInfoId,
                "age_rating_declaration": response.data.asAny
            ])
        } catch {
            return MCPResult.error("Failed to get age rating declaration: \(error.localizedDescription)")
        }
    }

    /// Lists calculated App Store age ratings for every territory of an App Info resource
    /// - Returns: JSON with territory ratings, included territory resources, paging metadata and continuation URL
    /// - Throws: CallTool.Result with error if inputs are invalid or the API call fails
    func listTerritoryAgeRatings(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'app_info_id' is missing")
        }

        do {
            let appInfoId = try requiredIdentifier("app_info_id", from: arguments)
            let effectiveLimit = try boundedInteger(
                "limit",
                from: arguments,
                default: 200,
                range: 1...200
            )
            let endpoint = "/v1/appInfos/\(try ASCPathSegment.encode(appInfoId))/territoryAgeRatings"
            let queryParameters = [
                "fields[territoryAgeRatings]": "appStoreAgeRating,territory",
                "fields[territories]": "currency",
                "include": "territory",
                "limit": String(effectiveLimit)
            ]

            let response: PassthroughAPIResponse
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(path: endpoint, query: queryParameters),
                    as: PassthroughAPIResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParameters,
                    as: PassthroughAPIResponse.self
                )
            }

            let ratings = try validatedJSONResourceCollection(
                response.data,
                expectedType: "territoryAgeRatings",
                context: "territory age rating collection"
            )
            let referencedTerritoryIDs = try Set(ratings.map { rating in
                let ratingObject = try validatedJSONResource(
                    rating,
                    expectedType: "territoryAgeRatings",
                    context: "territory age rating collection"
                )
                guard let relationships = ratingObject["relationships"] else {
                    throw AppLifecycleQueryArgumentError("Apple returned a territory age rating without territory linkage")
                }
                let territoryID = try validatedSingleRelationshipID(
                    relationships,
                    name: "territory",
                    expectedType: "territories",
                    context: "territory age rating linkage"
                )
                return "territories:\(territoryID)"
            })
            let includedTerritoryIDs = try validateIncludedResources(
                response.included,
                allowedTypes: ["territories"],
                context: "included territories"
            )
            guard referencedTerritoryIDs == includedTerritoryIDs else {
                throw AppLifecycleQueryArgumentError("Apple returned territory age ratings with incomplete or unrelated included territories")
            }

            var result: [String: Any] = [
                "success": true,
                "app_info_id": appInfoId,
                "territory_age_ratings": response.data.asAny,
                "count": ratings.count
            ]
            if let included = response.included {
                result["included_territories"] = included.map(\.asAny)
            }
            if case .object(let links) = response.links,
               case .string(let nextUrl) = links["next"] {
                result["next_url"] = nextUrl
            }
            if let meta = response.meta {
                result["meta"] = meta.asAny
                if let total = pagingTotal(from: meta) {
                    result["total"] = total
                }
            }

            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list territory age ratings: \(error.localizedDescription)")
        }
    }

    /// Updates app version attributes like release type, copyright, version string
    /// - Returns: JSON with updated version data and success status
    /// - Throws: CallTool.Result with error if version_id missing or API call fails
    func updateVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionId = arguments["version_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            let releaseType = try nullableString(
                "release_type",
                from: arguments,
                allowedValues: ["MANUAL", "AFTER_APPROVAL", "SCHEDULED"]
            )
            let earliestDate = try nullableString("earliest_release_date", from: arguments)
            let copyright = try nullableString("copyright", from: arguments)
            let versionString = try nullableString("version_string", from: arguments)
            let reviewType = try nullableString(
                "review_type",
                from: arguments,
                allowedValues: ["APP_STORE", "NOTARIZATION"]
            )
            let downloadable = try nullableBool("downloadable", from: arguments)
            let usesIdfa = try nullableBool("uses_idfa", from: arguments)

            guard releaseType != nil || earliestDate != nil || copyright != nil || versionString != nil || reviewType != nil || downloadable != nil || usesIdfa != nil else {
                return CallTool.Result(
                    content: [MCPContent.text("Error: No attributes to update")],
                    isError: true
                )
            }

            let request = UpdateAppStoreVersionRequest(
                id: versionId,
                releaseType: releaseType,
                earliestReleaseDate: earliestDate,
                copyright: copyright,
                versionString: versionString,
                reviewType: reviewType,
                downloadable: downloadable,
                usesIdfa: usesIdfa
            )

            let requestBody = try JSONEncoder().encode(request)
            let responseData = try await httpClient.patch(
                "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))",
                body: requestBody
            )
            let response: ASCAppStoreVersionResponse
            do {
                response = try JSONDecoder().decode(ASCAppStoreVersionResponse.self, from: responseData)
                try validateVersionResource(
                    response.data,
                    expectedID: versionId,
                    context: "app version update response"
                )
            } catch {
                return committedUnverifiedMutationFailure(
                    action: "app version update",
                    reason: error.localizedDescription,
                    details: ["version_id": versionId],
                    inspection: [
                        "tool": "app_versions_get",
                        "arguments": ["version_id": versionId]
                    ]
                )
            }

            let v = response.data
            let result: [String: Any] = [
                "success": true,
                "version": [
                    "id": v.id,
                    "platform": (v.attributes?.platform).jsonSafe,
                    "version_string": (v.attributes?.versionString).jsonSafe,
                    "state": (v.attributes?.appVersionState ?? v.attributes?.appStoreState).jsonSafe,
                    "appVersionState": (v.attributes?.appVersionState).jsonSafe,
                    "appStoreState": (v.attributes?.appStoreState).jsonSafe,
                    "app_version_state": (v.attributes?.appVersionState).jsonSafe,
                    "app_store_state": (v.attributes?.appStoreState).jsonSafe,
                    "release_type": (v.attributes?.releaseType).jsonSafe,
                    "review_type": (v.attributes?.reviewType).jsonSafe,
                    "earliest_release_date": (v.attributes?.earliestReleaseDate).jsonSafe,
                    "copyright": (v.attributes?.copyright).jsonSafe,
                    "downloadable": (v.attributes?.downloadable).jsonSafe,
                    "uses_idfa": (v.attributes?.usesIdfa).jsonSafe,
                    "created_date": (v.attributes?.createdDate).jsonSafe
                ] as [String: Any],
                "message": "Version updated successfully"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to update version: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Attaches a build to an app version for submission
    /// - Returns: JSON with success status and confirmation message
    /// - Throws: CallTool.Result with error if required parameters missing or API call fails
    func attachBuild(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionId = arguments["version_id"]?.stringValue,
              let buildId = arguments["build_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters missing: version_id, build_id")],
                isError: true
            )
        }

        do {
            let request = AttachBuildRequest(buildId: buildId)

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.patch(
                "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))/relationships/build",
                body: bodyData
            )

            let result: [String: Any] = [
                "success": true,
                "message": "Build \(buildId) attached to version \(versionId) successfully"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to attach build: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Submits an app version for App Store review using the Review Submissions API
    /// - Returns: JSON with submission details including submission ID and state
    /// - Throws: CallTool.Result with error if version_id missing or submission fails
    func submitForReview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionId = arguments["version_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        var submissionId: String?
        var failedStep = "create_review_submission"

        do {
            let versionResponse = try await httpClient.get(
                "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))",
                parameters: ["fields[appStoreVersions]": "app,platform,versionString,appVersionState"],
                as: ASCAppStoreVersionResponse.self
            )
            try validateVersionResource(
                versionResponse.data,
                expectedID: versionId,
                context: "review submission preflight"
            )
            guard let appData = versionResponse.data.relationships?.app?.data,
                  case .single(let appRef) = appData,
                  appRef.type == "apps",
                  isCanonicalResourceID(appRef.id) else {
                return MCPResult.error("Could not resolve app ownership from version '\(versionId)'.")
            }
            let appId = appRef.id
            if let providedAppId = arguments["app_id"]?.stringValue, providedAppId != appId {
                return MCPResult.error("Version '\(versionId)' belongs to app '\(appId)', not '\(providedAppId)'.")
            }

            let platform = arguments["platform"]?.stringValue
            if let platform,
               let versionPlatform = versionResponse.data.attributes?.platform,
               platform != versionPlatform {
                return MCPResult.error("Version '\(versionId)' is on platform '\(versionPlatform)', not '\(platform)'.")
            }

            // Step 1: Create review submission
            let submissionRequest = CreateReviewSubmissionRequest(platform: platform, appId: appId)
            let submissionBody = try JSONEncoder().encode(submissionRequest)
            let submissionData = try await httpClient.post("/v1/reviewSubmissions", body: submissionBody)
            let submissionResponse: SingleResourceResponse
            do {
                submissionResponse = try JSONDecoder().decode(SingleResourceResponse.self, from: submissionData)
                try validateSingleResource(
                    submissionResponse.data,
                    expectedType: "reviewSubmissions",
                    context: "review submission create response"
                )
                _ = try validatedOptionalSingleRelationshipID(
                    submissionResponse.data.relationships,
                    name: "app",
                    expectedType: "apps",
                    expectedID: appId,
                    context: "review submission app linkage"
                )
            } catch {
                return committedUnverifiedMutationFailure(
                    action: "review submission creation",
                    reason: error.localizedDescription,
                    details: [
                        "version_id": versionId,
                        "submission_id_known": false
                    ],
                    inspection: [
                        "instruction": "Inspect Review Submissions for this app and platform in App Store Connect before retrying."
                    ]
                )
            }
            submissionId = submissionResponse.data.id

            // Step 2: Add version as review submission item
            failedStep = "create_review_submission_item"
            guard let createdSubmissionId = submissionId else {
                return MCPResult.error("Review submission was created without an ID.")
            }
            let itemRequest = CreateReviewSubmissionItemRequest(submissionId: createdSubmissionId, versionId: versionId)
            let itemBodyData = try JSONEncoder().encode(itemRequest)
            let itemResponseData = try await httpClient.post("/v1/reviewSubmissionItems", body: itemBodyData)
            do {
                let itemResponse = try JSONDecoder().decode(PassthroughAPIResponse.self, from: itemResponseData)
                let item = try validatedJSONResource(
                    itemResponse.data,
                    expectedType: "reviewSubmissionItems",
                    context: "review submission item create response"
                )
                _ = try validatedOptionalSingleRelationshipID(
                    item["relationships"],
                    name: "appStoreVersion",
                    expectedType: "appStoreVersions",
                    expectedID: versionId,
                    context: "review submission item version linkage"
                )
                _ = try validatedOptionalSingleRelationshipID(
                    item["relationships"],
                    name: "reviewSubmission",
                    expectedType: "reviewSubmissions",
                    expectedID: createdSubmissionId,
                    context: "review submission item parent linkage"
                )
            } catch {
                return committedUnverifiedMutationFailure(
                    action: "review submission item creation",
                    reason: error.localizedDescription,
                    details: [
                        "version_id": versionId,
                        "submission_id": createdSubmissionId,
                        "submission_id_known": true,
                        "failed_step": failedStep,
                        "recovery_tools": ["app_versions_cancel_review"]
                    ],
                    inspection: [
                        "tool": "app_versions_cancel_review",
                        "arguments": ["review_submission_id": createdSubmissionId],
                        "instruction": "Inspect the submission in App Store Connect and cancel it before retrying when it remains open."
                    ]
                )
            }

            // Step 3: Confirm the submission
            failedStep = "confirm_review_submission"
            let confirmRequest = ConfirmReviewSubmissionRequest(submissionId: createdSubmissionId)
            let confirmBody = try JSONEncoder().encode(confirmRequest)
            let confirmData = try await httpClient.patch(
                "/v1/reviewSubmissions/\(try ASCPathSegment.encode(createdSubmissionId))",
                body: confirmBody
            )
            let confirmResponse: PassthroughAPIResponse
            do {
                confirmResponse = try JSONDecoder().decode(PassthroughAPIResponse.self, from: confirmData)
                let confirmedSubmission = try validatedJSONResource(
                    confirmResponse.data,
                    expectedType: "reviewSubmissions",
                    expectedID: createdSubmissionId,
                    context: "review submission confirmation response"
                )
                _ = try validatedOptionalSingleRelationshipID(
                    confirmedSubmission["relationships"],
                    name: "app",
                    expectedType: "apps",
                    expectedID: appId,
                    context: "confirmed review submission app linkage"
                )
            } catch {
                return committedUnverifiedMutationFailure(
                    action: "review submission confirmation",
                    reason: error.localizedDescription,
                    details: [
                        "version_id": versionId,
                        "submission_id": createdSubmissionId,
                        "submission_id_known": true,
                        "failed_step": failedStep
                    ],
                    inspection: [
                        "instruction": "Inspect review submission '\(createdSubmissionId)' in App Store Connect before canceling or retrying."
                    ]
                )
            }

            let result: [String: Any] = [
                "success": true,
                "submission": confirmResponse.data.asAny,
                "submission_id": createdSubmissionId,
                "message": "Version submitted for review successfully"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            if let submissionId = submissionId {
                return partialReviewSubmissionFailure(
                    submissionId: submissionId,
                    failedStep: failedStep,
                    error: error
                )
            }
            return MCPResult.error("Failed to submit for review: \(error.localizedDescription)")
        }
    }

    private func partialReviewSubmissionFailure(
        submissionId: String,
        failedStep: String,
        error: any Error
    ) -> CallTool.Result {
        MCPResult.jsonObject(
            [
                "success": false,
                "partial_success": true,
                "submission_id": submissionId,
                "failed_step": failedStep,
                "error": error.localizedDescription,
                "recovery_tools": [
                    "app_versions_cancel_review"
                ],
                "message": "Review submission was created, but the submit flow failed before completion. This MCP has no review-submission inspection or resume tool; use app_versions_cancel_review with review_submission_id set to the returned submission_id before retrying."
            ],
            isError: true
        )
    }

    /// Cancels an ongoing App Store review submission using the Review Submissions API
    /// - Returns: JSON with cancellation confirmation and submission details
    /// - Throws: CallTool.Result with error if review_submission_id missing or cancellation fails
    func cancelReview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let submissionId = arguments["review_submission_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'review_submission_id' is missing")],
                isError: true
            )
        }

        do {
            let request = CancelReviewSubmissionRequest(submissionId: submissionId)
            let requestBody = try JSONEncoder().encode(request)
            let responseData = try await httpClient.patch(
                "/v1/reviewSubmissions/\(try ASCPathSegment.encode(submissionId))",
                body: requestBody
            )
            let response: PassthroughAPIResponse
            do {
                response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)
                _ = try validatedJSONResource(
                    response.data,
                    expectedType: "reviewSubmissions",
                    expectedID: submissionId,
                    context: "review submission cancellation response"
                )
            } catch {
                return committedUnverifiedMutationFailure(
                    action: "review submission cancellation",
                    reason: error.localizedDescription,
                    details: ["review_submission_id": submissionId],
                    inspection: [
                        "instruction": "Inspect review submission '\(submissionId)' in App Store Connect before another cancellation attempt."
                    ]
                )
            }

            let result: [String: Any] = [
                "success": true,
                "submission": response.data.asAny,
                "message": "Review submission cancelled successfully"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to cancel review: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a phased release for gradual rollout of approved version
    /// - Returns: JSON with phased release details including ID and current state
    /// - Throws: CallTool.Result with error if version_id missing or creation fails
    func createPhasedRelease(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'version_id' is missing")
        }

        do {
            let versionId = try requiredIdentifier("version_id", from: arguments)
            let state = try optionalIdentifier("phased_release_state", from: arguments) ?? "INACTIVE"
            guard Self.phasedReleaseCreateStates.contains(state) else {
                throw AppLifecycleArgumentError(
                    "phased_release_state must be one of: \(Self.phasedReleaseCreateStates.sorted().joined(separator: ", "))"
                )
            }
            if state == "ACTIVE" {
                let confirmation = try optionalIdentifier("confirm_version_id", from: arguments)
                guard confirmation == versionId else {
                    return MCPResult.error(
                        "Creating an ACTIVE phased release starts distribution. Set confirm_version_id to the exact version_id to continue."
                    )
                }
            }

            let request = CreatePhasedReleaseRequest(versionId: versionId, state: state)
            let requestBody = try JSONEncoder().encode(request)
            let responseData = try await httpClient.post(
                "/v1/appStoreVersionPhasedReleases",
                body: requestBody
            )
            let response: PassthroughAPIResponse
            do {
                response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)
                _ = try validatedJSONResource(
                    response.data,
                    expectedType: "appStoreVersionPhasedReleases",
                    context: "phased release create response"
                )
            } catch {
                return committedUnverifiedMutationFailure(
                    action: "phased release creation",
                    reason: error.localizedDescription,
                    details: ["version_id": versionId, "phased_release_id_known": false],
                    inspection: [
                        "tool": "app_versions_get_phased_release",
                        "arguments": ["version_id": versionId]
                    ]
                )
            }

            let result: [String: Any] = [
                "success": true,
                "phased_release": response.data.asAny,
                "message": "Phased release created successfully"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create phased release: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets phased release info for an app version
    /// - Returns: JSON with phased release details including ID, state, startDate, currentDayNumber, totalPauseDuration
    /// - Throws: CallTool.Result with error if version_id missing or API call fails
    func getPhasedRelease(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionId = arguments["version_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            let response = try await httpClient.get(
                "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))/appStoreVersionPhasedRelease",
                parameters: [:],
                as: PassthroughAPIResponse.self
            )
            _ = try validatedJSONResource(
                response.data,
                expectedType: "appStoreVersionPhasedReleases",
                context: "phased release detail"
            )

            let result: [String: Any] = [
                "success": true,
                "phased_release": response.data.asAny
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get phased release: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates phased release state to pause, resume or complete rollout
    /// - Returns: JSON with updated phased release state and percentage
    /// - Throws: CallTool.Result with error if required parameters missing or update fails
    func updatePhasedRelease(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters missing: phased_release_id, phased_release_state")
        }

        do {
            let phasedReleaseId = try requiredIdentifier("phased_release_id", from: arguments)
            let state = try requiredIdentifier("phased_release_state", from: arguments)
            guard Self.phasedReleaseUpdateStates.contains(state) else {
                throw AppLifecycleArgumentError(
                    "phased_release_state must be one of: \(Self.phasedReleaseUpdateStates.sorted().joined(separator: ", "))"
                )
            }
            if state == "ACTIVE" || state == "COMPLETE" {
                let confirmation = try optionalCanonicalIdentifier("confirm_phased_release_id", from: arguments)
                guard confirmation == phasedReleaseId else {
                    let consequence = state == "ACTIVE"
                        ? "ACTIVE starts or resumes distribution"
                        : "COMPLETE immediately releases the version to all users"
                    return MCPResult.error(
                        "\(consequence). Set confirm_phased_release_id to the exact phased_release_id to continue."
                    )
                }
            }

            let request = UpdatePhasedReleaseRequest(phasedReleaseId: phasedReleaseId, state: state)
            let requestBody = try JSONEncoder().encode(request)
            let responseData = try await httpClient.patch(
                "/v1/appStoreVersionPhasedReleases/\(try ASCPathSegment.encode(phasedReleaseId))",
                body: requestBody
            )
            let response: PassthroughAPIResponse
            do {
                response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)
                _ = try validatedJSONResource(
                    response.data,
                    expectedType: "appStoreVersionPhasedReleases",
                    expectedID: phasedReleaseId,
                    context: "phased release update response"
                )
            } catch {
                return committedUnverifiedMutationFailure(
                    action: "phased release update",
                    reason: error.localizedDescription,
                    details: ["phased_release_id": phasedReleaseId],
                    inspection: [
                        "instruction": "Inspect phased release '\(phasedReleaseId)' in App Store Connect before another state transition."
                    ]
                )
            }

            let result: [String: Any] = [
                "success": true,
                "phased_release": response.data.asAny,
                "message": "Phased release state updated to \(state)"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to update phased release: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes an eligible planned phased release after exact resource-ID confirmation.
    /// - Returns: JSON confirmation, or a structured error that distinguishes a rejected request from an unknown commit outcome.
    /// - Throws: This handler converts validation and App Store Connect failures into `CallTool.Result` errors.
    func deletePhasedRelease(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters are missing: phased_release_id, confirm_phased_release_id")
        }

        let phasedReleaseId: String
        do {
            phasedReleaseId = try requiredCanonicalIdentifier("phased_release_id", from: arguments)
            let confirmation = try requiredCanonicalIdentifier("confirm_phased_release_id", from: arguments)
            guard confirmation == phasedReleaseId else {
                return MCPResult.error(
                    "Deleting a phased release cancels an eligible planned rollout. Set confirm_phased_release_id to the exact phased_release_id to continue."
                )
            }
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        let endpoint: String
        do {
            endpoint = "/v1/appStoreVersionPhasedReleases/\(try ASCPathSegment.encode(phasedReleaseId))"
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        do {
            _ = try await httpClient.delete(
                endpoint
            )
            return MCPResult.jsonObject([
                "success": true,
                "deletionState": "confirmed",
                "outcomeUnknown": false,
                "retrySafe": false,
                "phased_release_id": phasedReleaseId,
                "message": "Phased release deleted successfully"
            ])
        } catch {
            return deletionFailure(
                resourceName: "phased release",
                targetField: "phased_release_id",
                targetID: phasedReleaseId,
                error: error,
                inspection: .object([
                    "tool": .string("app_versions_get_phased_release"),
                    "requiredArguments": .array([.string("version_id")]),
                    "instruction": .string("Inspect the owning app version's phased-release relationship, or verify the rollout in App Store Connect, before another delete attempt.")
                ])
            )
        }
    }

    /// Releases an approved version to the App Store immediately
    /// - Returns: JSON with release confirmation and version state change
    /// - Throws: CallTool.Result with error if version_id missing or release fails
    func releaseVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionId = arguments["version_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            let versionResponse = try await httpClient.get(
                "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))",
                parameters: ["fields[appStoreVersions]": "platform,versionString,appVersionState"],
                as: ASCAppStoreVersionResponse.self
            )
            try validateVersionResource(
                versionResponse.data,
                expectedID: versionId,
                context: "release preflight"
            )
            let attributes = versionResponse.data.attributes
            let versionString = attributes?.versionString
            let appVersionState = attributes?.appVersionState
            let platform = attributes?.platform
            let expectedState = "PENDING_DEVELOPER_RELEASE"

            guard appVersionState == expectedState else {
                return releasePreflightError(
                    reason: "invalid_app_version_state",
                    message: "Version must be in \(expectedState) before manual release.",
                    versionId: versionId,
                    versionString: versionString,
                    platform: platform,
                    appVersionState: appVersionState
                )
            }

            guard let versionString, !versionString.isEmpty else {
                return releasePreflightError(
                    reason: "missing_version_string",
                    message: "Could not read versionString needed for release confirmation.",
                    versionId: versionId,
                    versionString: versionString,
                    platform: platform,
                    appVersionState: appVersionState
                )
            }

            guard let confirmation = arguments["confirm_version_string"]?.stringValue else {
                return releasePreflightError(
                    reason: "confirmation_required",
                    message: "Re-run with confirm_version_string exactly equal to \(versionString) to release this version.",
                    versionId: versionId,
                    versionString: versionString,
                    platform: platform,
                    appVersionState: appVersionState
                )
            }

            guard confirmation == versionString else {
                return releasePreflightError(
                    reason: "confirmation_mismatch",
                    message: "confirm_version_string must exactly match \(versionString).",
                    versionId: versionId,
                    versionString: versionString,
                    platform: platform,
                    appVersionState: appVersionState
                )
            }

            let request = CreateReleaseRequest(versionId: versionId)
            let requestBody = try JSONEncoder().encode(request)
            let responseData = try await httpClient.post(
                "/v1/appStoreVersionReleaseRequests",
                body: requestBody
            )
            let response: PassthroughAPIResponse
            do {
                response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)
                _ = try validatedJSONResource(
                    response.data,
                    expectedType: "appStoreVersionReleaseRequests",
                    context: "release request create response"
                )
            } catch {
                return committedUnverifiedMutationFailure(
                    action: "release request creation",
                    reason: error.localizedDescription,
                    details: ["version_id": versionId],
                    inspection: [
                        "tool": "app_versions_get",
                        "arguments": ["version_id": versionId],
                        "instruction": "Inspect the exact version state before any further release attempt."
                    ]
                )
            }

            let result: [String: Any] = [
                "success": true,
                "release_request": response.data.asAny,
                "version_id": versionId,
                "version_string": versionString,
                "platform": platform.jsonSafe,
                "app_version_state": appVersionState.jsonSafe,
                "message": "Version released to App Store successfully"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error("Failed to release version: \(error.localizedDescription)")
        }
    }

    private func releasePreflightError(
        reason: String,
        message: String,
        versionId: String,
        versionString: String?,
        platform: String?,
        appVersionState: String?
    ) -> CallTool.Result {
        MCPResult.jsonObject(
            [
                "success": false,
                "reason": reason,
                "message": message,
                "version_id": versionId,
                "version_string": versionString.jsonSafe,
                "platform": platform.jsonSafe,
                "app_version_state": appVersionState.jsonSafe,
                "required_app_version_state": "PENDING_DEVELOPER_RELEASE"
            ],
            text: "Error: \(message)",
            isError: true
        )
    }

    /// Sets or updates review details for App Store reviewers including contact info and demo account
    /// - Returns: JSON with review details and action taken (created/updated)
    /// - Throws: CallTool.Result with error if version_id missing or API call fails
    func setReviewDetails(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        let versionId: String
        do {
            versionId = try requiredIdentifier("version_id", from: arguments)
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        if arguments["attachment_file_id"] != nil {
            return MCPResult.error("attachment_file_id is not accepted by Apple's review detail API. Create or update the review details first, then use review_attachments_upload with the returned review detail ID.")
        }

        let attrs: ReviewDetailAttributes
        do {
            attrs = ReviewDetailAttributes(
                contactFirstName: try nullableString("contact_first_name", from: arguments),
                contactLastName: try nullableString("contact_last_name", from: arguments),
                contactPhone: try nullableString("contact_phone", from: arguments),
                contactEmail: try nullableString("contact_email", from: arguments),
                demoAccountName: try nullableString("demo_account_name", from: arguments),
                demoAccountPassword: try nullableString("demo_account_password", from: arguments),
                demoAccountRequired: try nullableBool("demo_account_required", from: arguments),
                notes: try nullableString("notes", from: arguments)
            )
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        do {
            let existingReviewDetailId = try await resolveReviewDetailId(versionId: versionId)

            let response: PassthroughAPIResponse
            let message: String

            if let reviewDetailId = existingReviewDetailId {
                // Review details exist - update them with PATCH
                let request = UpdateAppStoreReviewDetailRequest(
                    reviewDetailId: reviewDetailId,
                    attributes: .init(
                        contactFirstName: attrs.contactFirstName,
                        contactLastName: attrs.contactLastName,
                        contactPhone: attrs.contactPhone,
                        contactEmail: attrs.contactEmail,
                        demoAccountName: attrs.demoAccountName,
                        demoAccountPassword: attrs.demoAccountPassword,
                        demoAccountRequired: attrs.demoAccountRequired,
                        notes: attrs.notes
                    )
                )
                let requestBody = try JSONEncoder().encode(request)
                let responseData = try await httpClient.patch(
                    "/v1/appStoreReviewDetails/\(try ASCPathSegment.encode(reviewDetailId))",
                    body: requestBody
                )
                do {
                    response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)
                    let updatedReviewDetail = try validatedJSONResource(
                        response.data,
                        expectedType: "appStoreReviewDetails",
                        expectedID: reviewDetailId,
                        context: "review detail update response"
                    )
                    _ = try validatedOptionalSingleRelationshipID(
                        updatedReviewDetail["relationships"],
                        name: "appStoreVersion",
                        expectedType: "appStoreVersions",
                        expectedID: versionId,
                        context: "updated review detail parent linkage"
                    )
                } catch {
                    return committedUnverifiedMutationFailure(
                        action: "review detail update",
                        reason: error.localizedDescription,
                        details: [
                            "version_id": versionId,
                            "review_detail_id": reviewDetailId
                        ],
                        inspection: [
                            "instruction": "Inspect the review information for version '\(versionId)' in App Store Connect before retrying."
                        ]
                    )
                }
                message = "Review details updated successfully"
            } else {
                // Review details don't exist - create new with POST
                let request = CreateAppStoreReviewDetailRequest(
                    versionId: versionId,
                    attributes: .init(
                        contactFirstName: attrs.contactFirstName,
                        contactLastName: attrs.contactLastName,
                        contactPhone: attrs.contactPhone,
                        contactEmail: attrs.contactEmail,
                        demoAccountName: attrs.demoAccountName,
                        demoAccountPassword: attrs.demoAccountPassword,
                        demoAccountRequired: attrs.demoAccountRequired,
                        notes: attrs.notes
                    )
                )
                let requestBody = try JSONEncoder().encode(request)
                let responseData = try await httpClient.post(
                    "/v1/appStoreReviewDetails",
                    body: requestBody
                )
                do {
                    response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)
                    let createdReviewDetail = try validatedJSONResource(
                        response.data,
                        expectedType: "appStoreReviewDetails",
                        context: "review detail create response"
                    )
                    _ = try validatedOptionalSingleRelationshipID(
                        createdReviewDetail["relationships"],
                        name: "appStoreVersion",
                        expectedType: "appStoreVersions",
                        expectedID: versionId,
                        context: "created review detail parent linkage"
                    )
                } catch {
                    return committedUnverifiedMutationFailure(
                        action: "review detail creation",
                        reason: error.localizedDescription,
                        details: [
                            "version_id": versionId,
                            "review_detail_id_known": false
                        ],
                        inspection: [
                            "instruction": "Inspect the review information for version '\(versionId)' in App Store Connect before retrying."
                        ]
                    )
                }
                message = "Review details created successfully"
            }

            let result: [String: Any] = [
                "success": true,
                "review_details": response.data.asAny,
                "message": message,
                "action": existingReviewDetailId != nil ? "updated" : "created"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to set review details: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates an app-level age rating declaration using an App Info ID or a compatible version lookup
    /// - Returns: JSON with the updated age rating details and selected App Info ID
    /// - Throws: CallTool.Result with error if identifiers or attributes are invalid, or an API call fails
    func updateAgeRating(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("At least one of app_info_id or version_id is required")
        }

        let versionId: String?
        let directAppInfoId: String?
        do {
            versionId = try optionalIdentifier("version_id", from: arguments)
            directAppInfoId = try optionalIdentifier("app_info_id", from: arguments)
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        guard versionId != nil || directAppInfoId != nil else {
            return MCPResult.error("At least one of app_info_id or version_id is required")
        }

        let intensityValues = Set(["NONE", "INFREQUENT_OR_MILD", "FREQUENT_OR_INTENSE", "INFREQUENT", "FREQUENT"])
        let intensityFields: [String: String] = [
            "alcohol_tobacco_or_drug_use": "alcoholTobaccoOrDrugUseOrReferences",
            "contests": "contests",
            "gambling_simulated": "gamblingSimulated",
            "horror_fear_themes": "horrorOrFearThemes",
            "mature_suggestive_themes": "matureOrSuggestiveThemes",
            "medical_treatment_information": "medicalOrTreatmentInformation",
            "profanity_crude_humor": "profanityOrCrudeHumor",
            "sexual_content_nudity": "sexualContentOrNudity",
            "sexual_content_graphic_nudity": "sexualContentGraphicAndNudity",
            "violence_cartoon": "violenceCartoonOrFantasy",
            "violence_realistic": "violenceRealistic",
            "violence_realistic_prolonged": "violenceRealisticProlongedGraphicOrSadistic",
            "guns_or_other_weapons": "gunsOrOtherWeapons"
        ]
        let boolFields: [String: String] = [
            "gambling": "gambling",
            "unrestricted_web_access": "unrestrictedWebAccess",
            "advertising": "advertising",
            "age_assurance": "ageAssurance",
            "health_or_wellness_topics": "healthOrWellnessTopics",
            "loot_box": "lootBox",
            "messaging_and_chat": "messagingAndChat",
            "parental_controls": "parentalControls",
            "social_media": "socialMedia",
            "social_media_age_restricted": "socialMediaAgeRestricted",
            "user_generated_content": "userGeneratedContent"
        ]

        var attributes: [String: NullableAttributeValue] = [:]
        do {
            for (toolField, appleField) in intensityFields {
                if let value = try nullableString(toolField, from: arguments, allowedValues: intensityValues) {
                    attributes[appleField] = value
                }
            }

            for (toolField, appleField) in boolFields {
                if let value = try nullableBool(toolField, from: arguments) {
                    attributes[appleField] = value
                }
            }

            if let value = try nullableString(
                "kids_age_band",
                from: arguments,
                allowedValues: ["FIVE_AND_UNDER", "SIX_TO_EIGHT", "NINE_TO_ELEVEN"]
            ) {
                attributes["kidsAgeBand"] = value
            }
            if let value = try nullableString(
                "age_rating_override",
                from: arguments,
                allowedValues: ["NONE", "NINE_PLUS", "THIRTEEN_PLUS", "SIXTEEN_PLUS", "EIGHTEEN_PLUS", "UNRATED"]
            ) {
                attributes["ageRatingOverrideV2"] = value
            }
            if let value = try nullableString(
                "korea_age_rating_override",
                from: arguments,
                allowedValues: ["NONE", "FIFTEEN_PLUS", "NINETEEN_PLUS"]
            ) {
                attributes["koreaAgeRatingOverride"] = value
            }
            if let value = try nullableAbsoluteURI("developer_age_rating_info_url", from: arguments) {
                attributes["developerAgeRatingInfoUrl"] = value
            }
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        guard !attributes.isEmpty else {
            return MCPResult.error("No age rating attributes to update")
        }

        do {
            let appInfoId: String
            if let directAppInfoId {
                appInfoId = directAppInfoId
            } else if let versionId {
                let versionResponse = try await httpClient.get(
                    "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))",
                    parameters: ["fields[appStoreVersions]": "app,appVersionState"],
                    as: ASCAppStoreVersionResponse.self
                )
                try validateVersionResource(
                    versionResponse.data,
                    expectedID: versionId,
                    context: "age rating version lookup"
                )

                guard let appRelationship = versionResponse.data.relationships?.app?.data,
                      case .single(let app) = appRelationship,
                      app.type == "apps",
                      isCanonicalResourceID(app.id) else {
                    return MCPResult.error("Could not resolve the owning app from version \(versionId). Provide app_info_id from app_info_list.")
                }

                guard appInfoState(for: versionResponse.data.attributes?.appVersionState) != nil else {
                    let versionState = versionResponse.data.attributes?.appVersionState ?? "UNKNOWN"
                    return MCPResult.error("Version state \(versionState) cannot be safely mapped to App Info. Provide app_info_id from app_info_list.")
                }

                let appInfoPath = "/v1/apps/\(try ASCPathSegment.encode(app.id))/appInfos"
                let appInfoParameters = [
                    "fields[appInfos]": "state,app",
                    "limit": "200"
                ]
                let appInfoScope = PaginationScope.strict(
                    path: appInfoPath,
                    query: appInfoParameters
                )
                var appInfoPage: ASCAppInfosResponse? = try await httpClient.get(
                    appInfoPath,
                    parameters: appInfoParameters,
                    as: ASCAppInfosResponse.self
                )
                var allAppInfos: [ASCAppInfo] = []
                var seenAppInfoNextURLs: Set<String> = []
                while let page = appInfoPage {
                    allAppInfos.append(contentsOf: page.data)
                    guard let links = page.links else {
                        throw AppLifecycleQueryArgumentError(
                            "Apple returned an App Info page without required pagination links"
                        )
                    }
                    if let next = links.next {
                        guard seenAppInfoNextURLs.insert(next).inserted else {
                            throw AppLifecycleQueryArgumentError(
                                "Apple returned a repeated App Info continuation URL"
                            )
                        }
                        appInfoPage = try await httpClient.getPage(
                            next,
                            scope: appInfoScope,
                            as: ASCAppInfosResponse.self
                        )
                    } else {
                        appInfoPage = nil
                    }
                }
                var appInfoIdentities = Set<String>()
                for appInfo in allAppInfos {
                    try validateResourceIdentity(
                        type: appInfo.type,
                        id: appInfo.id,
                        expectedType: "appInfos",
                        context: "App Info collection item"
                    )
                    guard appInfoIdentities.insert("\(appInfo.type):\(appInfo.id)").inserted else {
                        throw AppLifecycleQueryArgumentError(
                            "Apple returned duplicate App Info resource identity"
                        )
                    }
                    guard let appRelationship = appInfo.relationships?.app?.data else {
                        throw AppLifecycleQueryArgumentError("Apple returned an App Info without owning app linkage")
                    }
                    try validateResourceIdentity(
                        type: appRelationship.type,
                        id: appRelationship.id,
                        expectedType: "apps",
                        expectedID: app.id,
                        context: "App Info parent linkage"
                    )
                }

                guard let appInfo = selectAppInfo(
                    from: allAppInfos,
                    versionState: versionResponse.data.attributes?.appVersionState
                ) else {
                    let candidates = allAppInfos.prefix(20).map { info in
                        "\(info.id):\(info.attributes?.state ?? "UNKNOWN")"
                    }.joined(separator: ", ")
                    let remaining = max(0, allAppInfos.count - 20)
                    let suffix = remaining > 0 ? " (+\(remaining) more)" : ""
                    return MCPResult.error("Could not safely select App Info for version \(versionId). Provide app_info_id from app_info_list. Candidates: \(candidates.isEmpty ? "none" : candidates)\(suffix).")
                }
                appInfoId = appInfo.id
            } else {
                return MCPResult.error("At least one of app_info_id or version_id is required")
            }

            let ageRatingResponse = try await httpClient.get(
                "/v1/appInfos/\(try ASCPathSegment.encode(appInfoId))/ageRatingDeclaration",
                parameters: [:],
                as: SingleResourceResponse.self
            )
            try validateSingleResource(
                ageRatingResponse.data,
                expectedType: "ageRatingDeclarations",
                context: "age rating declaration lookup"
            )
            let ageRatingId = ageRatingResponse.data.id

            let request = UpdateAgeRatingDeclarationRequest(
                ageRatingId: ageRatingId,
                attributes: attributes
            )
            let requestBody = try JSONEncoder().encode(request)
            let responseData = try await httpClient.patch(
                "/v1/ageRatingDeclarations/\(try ASCPathSegment.encode(ageRatingId))",
                body: requestBody
            )
            let response: PassthroughAPIResponse
            do {
                response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)
                _ = try validatedJSONResource(
                    response.data,
                    expectedType: "ageRatingDeclarations",
                    expectedID: ageRatingId,
                    context: "age rating declaration update response"
                )
            } catch {
                return committedUnverifiedMutationFailure(
                    action: "age rating declaration update",
                    reason: error.localizedDescription,
                    details: [
                        "app_info_id": appInfoId,
                        "age_rating_declaration_id": ageRatingId
                    ],
                    inspection: [
                        "tool": "app_versions_get_age_rating_declaration",
                        "arguments": ["app_info_id": appInfoId]
                    ]
                )
            }

            let result: [String: Any] = [
                "success": true,
                "age_rating": response.data.asAny,
                "app_info_id": appInfoId,
                "message": "Age rating declaration updated successfully",
                "action": "updated"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to update age rating: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes an app store version after exact resource-ID confirmation.
    /// - Returns: JSON confirmation, or a structured error that distinguishes a rejected request from an unknown commit outcome.
    /// - Throws: This handler converts validation and App Store Connect failures into `CallTool.Result` errors.
    func deleteVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters are missing: version_id, confirm_version_id")
        }

        let versionId: String
        do {
            versionId = try requiredCanonicalIdentifier("version_id", from: arguments)
            let confirmation = try requiredCanonicalIdentifier("confirm_version_id", from: arguments)
            guard confirmation == versionId else {
                return MCPResult.error(
                    "Deleting an app store version is irreversible. Set confirm_version_id to the exact version_id to continue."
                )
            }
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        let endpoint: String
        do {
            endpoint = "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))"
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        do {
            _ = try await httpClient.delete(endpoint)

            let result: [String: Any] = [
                "success": true,
                "deletionState": "confirmed",
                "outcomeUnknown": false,
                "retrySafe": false,
                "version_id": versionId,
                "message": "Version '\(versionId)' deleted successfully"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return deletionFailure(
                resourceName: "app store version",
                targetField: "version_id",
                targetID: versionId,
                error: error,
                inspection: .object([
                    "tool": .string("app_versions_get"),
                    "arguments": .object(["version_id": .string(versionId)]),
                    "instruction": .string("Inspect this exact version before another delete attempt.")
                ])
            )
        }
    }
}

private struct AppLifecycleQueryArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private enum AppLifecycleDeletionFailureState: String {
    case committedUnverified = "committed_unverified"
    case commitUnknown = "commit_unknown"
    case rejected

    var operationCommitState: String {
        switch self {
        case .committedUnverified:
            return "committed_unverified"
        case .commitUnknown:
            return "unknown"
        case .rejected:
            return "rejected"
        }
    }
}

// MARK: - Private Helpers

private extension AppLifecycleWorker {
    func resolveReviewDetailId(versionId: String) async throws -> String? {
        do {
            let response = try await httpClient.get(
                "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))/appStoreReviewDetail",
                parameters: ["fields[appStoreReviewDetails]": "appStoreVersion"],
                as: SingleResourceResponse.self
            )
            try validateSingleResource(
                response.data,
                expectedType: "appStoreReviewDetails",
                context: "review detail lookup"
            )
            _ = try validatedSingleRelationshipID(
                response.data.relationships,
                name: "appStoreVersion",
                expectedType: "appStoreVersions",
                expectedID: versionId,
                context: "review detail parent linkage"
            )
            return response.data.id
        } catch let error as ASCError {
            switch error {
            case .api(_, 404), .apiResponse(_, 404):
                let versionResponse = try await httpClient.get(
                    "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))",
                    parameters: ["fields[appStoreVersions]": "versionString"],
                    as: ASCAppStoreVersionResponse.self
                )
                try validateVersionResource(
                    versionResponse.data,
                    expectedID: versionId,
                    context: "review detail parent lookup"
                )
                return nil
            default:
                throw error
            }
        }
    }

    func selectAppInfo(from appInfos: [ASCAppInfo], versionState: String?) -> ASCAppInfo? {
        guard let targetState = appInfoState(for: versionState) else {
            return nil
        }
        let exactMatches = appInfos.filter { $0.attributes?.state == targetState }
        return exactMatches.count == 1 ? exactMatches[0] : nil
    }

    func validateVersionResource(
        _ version: ASCAppStoreVersion,
        expectedID: String,
        context: String
    ) throws {
        try validateResourceIdentity(
            type: version.type,
            id: version.id,
            expectedType: "appStoreVersions",
            expectedID: expectedID,
            context: context
        )
    }

    func validateSingleResource(
        _ resource: SingleResourceResponse.ResourceData,
        expectedType: String,
        expectedID: String? = nil,
        context: String
    ) throws {
        try validateResourceIdentity(
            type: resource.type,
            id: resource.id,
            expectedType: expectedType,
            expectedID: expectedID,
            context: context
        )
    }

    func validateResourceIdentity(
        type: String,
        id: String,
        expectedType: String,
        expectedID: String? = nil,
        context: String
    ) throws {
        guard type == expectedType else {
            throw AppLifecycleQueryArgumentError(
                "Apple returned unexpected resource type '\(type)' for \(context); expected '\(expectedType)'"
            )
        }
        guard isCanonicalResourceID(id) else {
            throw AppLifecycleQueryArgumentError("Apple returned an empty or malformed resource ID for \(context)")
        }
        if let expectedID, id != expectedID {
            throw AppLifecycleQueryArgumentError(
                "Apple returned resource ID '\(id)' for \(context); expected '\(expectedID)'"
            )
        }
    }

    func validatedJSONResource(
        _ value: JSONValue,
        expectedType: String,
        expectedID: String? = nil,
        context: String
    ) throws -> [String: JSONValue] {
        guard case .object(let object) = value,
              case .string(let type)? = object["type"],
              case .string(let id)? = object["id"] else {
            throw AppLifecycleQueryArgumentError("Apple returned malformed JSON:API data for \(context)")
        }
        try validateResourceIdentity(
            type: type,
            id: id,
            expectedType: expectedType,
            expectedID: expectedID,
            context: context
        )
        return object
    }

    func validatedJSONResourceCollection(
        _ value: JSONValue,
        expectedType: String,
        context: String
    ) throws -> [JSONValue] {
        guard case .array(let resources) = value else {
            throw AppLifecycleQueryArgumentError("Apple returned non-array JSON:API data for \(context)")
        }
        var identities = Set<String>()
        for resource in resources {
            let object = try validatedJSONResource(
                resource,
                expectedType: expectedType,
                context: context
            )
            guard case .string(let id)? = object["id"],
                  identities.insert("\(expectedType):\(id)").inserted else {
                throw AppLifecycleQueryArgumentError("Apple returned duplicate resource identity in \(context)")
            }
        }
        return resources
    }

    func validatedSingleRelationshipID(
        _ relationships: JSONValue,
        name: String,
        expectedType: String,
        expectedID: String? = nil,
        context: String
    ) throws -> String {
        guard case .object(let relationshipObject) = relationships,
              case .object(let relationship)? = relationshipObject[name],
              let data = relationship["data"] else {
            throw AppLifecycleQueryArgumentError("Apple returned malformed or missing \(context)")
        }
        let resource = try validatedJSONResource(
            data,
            expectedType: expectedType,
            expectedID: expectedID,
            context: context
        )
        guard case .string(let id)? = resource["id"] else {
            throw AppLifecycleQueryArgumentError("Apple returned malformed or missing \(context)")
        }
        return id
    }

    func validatedSingleRelationshipID(
        _ relationships: JSONValue?,
        name: String,
        expectedType: String,
        expectedID: String? = nil,
        context: String
    ) throws -> String {
        guard let relationships else {
            throw AppLifecycleQueryArgumentError("Apple returned malformed or missing \(context)")
        }
        return try validatedSingleRelationshipID(
            relationships,
            name: name,
            expectedType: expectedType,
            expectedID: expectedID,
            context: context
        )
    }

    func validatedOptionalSingleRelationshipID(
        _ relationships: JSONValue?,
        name: String,
        expectedType: String,
        expectedID: String? = nil,
        context: String
    ) throws -> String? {
        guard let relationships else {
            return nil
        }
        guard case .object(let relationshipObject) = relationships else {
            throw AppLifecycleQueryArgumentError("Apple returned malformed relationships for \(context)")
        }
        guard let relationshipValue = relationshipObject[name] else {
            return nil
        }
        guard case .object(let relationship) = relationshipValue else {
            throw AppLifecycleQueryArgumentError("Apple returned malformed \(context)")
        }
        guard let data = relationship["data"] else {
            return nil
        }
        if case .null = data {
            return nil
        }
        let resource = try validatedJSONResource(
            data,
            expectedType: expectedType,
            expectedID: expectedID,
            context: context
        )
        guard case .string(let id)? = resource["id"] else {
            throw AppLifecycleQueryArgumentError("Apple returned malformed \(context)")
        }
        return id
    }

    func validateVersionIncludedResources(
        versions: [JSONValue],
        included: [JSONValue]?,
        context: String
    ) throws {
        let relationshipTypes = [
            "build": "builds",
            "appStoreVersionPhasedRelease": "appStoreVersionPhasedReleases"
        ]
        var referencedIdentities = Set<String>()

        for version in versions {
            let versionObject = try validatedJSONResource(
                version,
                expectedType: "appStoreVersions",
                context: context
            )
            guard let relationships = versionObject["relationships"] else {
                continue
            }
            guard case .object(let relationshipObject) = relationships else {
                throw AppLifecycleQueryArgumentError("Apple returned malformed version relationships in \(context)")
            }
            for (name, expectedType) in relationshipTypes {
                guard let relationshipValue = relationshipObject[name] else {
                    continue
                }
                guard case .object(let relationship) = relationshipValue else {
                    throw AppLifecycleQueryArgumentError(
                        "Apple returned malformed \(name) linkage in \(context)"
                    )
                }
                guard let data = relationship["data"] else {
                    continue
                }
                if case .null = data {
                    continue
                }
                let linkedResource = try validatedJSONResource(
                    data,
                    expectedType: expectedType,
                    context: "\(context) \(name) linkage"
                )
                guard case .string(let id)? = linkedResource["id"] else {
                    throw AppLifecycleQueryArgumentError(
                        "Apple returned malformed \(name) linkage in \(context)"
                    )
                }
                referencedIdentities.insert("\(expectedType):\(id)")
            }
        }

        let includedIdentities = try validateIncludedResources(
            included,
            allowedTypes: Set(relationshipTypes.values),
            context: "\(context) included resources"
        )
        guard referencedIdentities == includedIdentities else {
            throw AppLifecycleQueryArgumentError(
                "Apple returned incomplete or unrelated included resources in \(context)"
            )
        }
    }

    func validateIncludedResources(
        _ resources: [JSONValue]?,
        allowedTypes: Set<String>,
        context: String
    ) throws -> Set<String> {
        var identities = Set<String>()
        for resource in resources ?? [] {
            guard case .object(let object) = resource,
                  case .string(let type)? = object["type"],
                  allowedTypes.contains(type),
                  case .string(let id)? = object["id"] else {
                throw AppLifecycleQueryArgumentError("Apple returned malformed or unexpected resource in \(context)")
            }
            try validateResourceIdentity(
                type: type,
                id: id,
                expectedType: type,
                context: context
            )
            guard identities.insert("\(type):\(id)").inserted else {
                throw AppLifecycleQueryArgumentError("Apple returned duplicate resource identity in \(context)")
            }
        }
        return identities
    }

    func isCanonicalResourceID(_ id: String) -> Bool {
        guard !id.isEmpty,
              id == id.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return (try? ASCPathSegment.encode(id)) != nil
    }

    func committedUnverifiedMutationFailure(
        action: String,
        reason: String,
        details: [String: Any],
        inspection: [String: Any]
    ) -> CallTool.Result {
        var payload = details
        payload["success"] = false
        payload["operationCommitState"] = "committed_unverified"
        payload["operationCommitted"] = true
        payload["retrySafe"] = false
        payload["error"] = Redactor.redact(reason)
        payload["inspection"] = inspection
        return MCPResult.jsonObject(
            payload,
            text: "Error: Apple accepted the \(action), but the returned resource identity could not be verified. Inspect the existing resource before retrying.",
            isError: true
        )
    }

    func appInfoState(for versionState: String?) -> String? {
        guard let versionState else {
            return nil
        }

        switch versionState {
        case "PENDING_APPLE_RELEASE", "PENDING_DEVELOPER_RELEASE", "PROCESSING_FOR_DISTRIBUTION":
            return "PENDING_RELEASE"
        case "METADATA_REJECTED":
            return "REJECTED"
        case "INVALID_BINARY":
            return nil
        case "REPLACED_WITH_NEW_VERSION":
            return "REPLACED_WITH_NEW_INFO"
        default:
            return versionState
        }
    }

    func requiredIdentifier(_ name: String, from arguments: [String: Value]) throws -> String {
        guard let value = try optionalIdentifier(name, from: arguments) else {
            throw AppLifecycleArgumentError("Required parameter '\(name)' is missing")
        }
        return value
    }

    func requiredCanonicalIdentifier(_ name: String, from arguments: [String: Value]) throws -> String {
        guard let value = try optionalCanonicalIdentifier(name, from: arguments) else {
            throw AppLifecycleArgumentError("Required parameter '\(name)' is missing")
        }
        return value
    }

    func optionalCanonicalIdentifier(_ name: String, from arguments: [String: Value]) throws -> String? {
        guard let value = try optionalIdentifier(name, from: arguments) else {
            return nil
        }
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw AppLifecycleArgumentError("\(name) must not contain leading or trailing whitespace")
        }
        return value
    }

    func optionalIdentifier(_ name: String, from arguments: [String: Value]) throws -> String? {
        guard let value = arguments[name] else {
            return nil
        }
        guard let string = value.stringValue,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppLifecycleArgumentError("\(name) must be a non-empty string")
        }
        return string
    }

    func deletionFailure(
        resourceName: String,
        targetField: String,
        targetID: String,
        error: Error,
        inspection: Value
    ) -> CallTool.Result {
        let state = deletionFailureState(error)
        let message: String
        switch state {
        case .committedUnverified:
            message = "Apple accepted the \(resourceName) delete request, but completion is unverified. Do not retry until the exact target is inspected."
        case .commitUnknown:
            message = "The \(resourceName) delete outcome is unknown. Do not retry until the exact target is inspected."
        case .rejected:
            message = "Failed to delete \(resourceName): \(error.localizedDescription)"
        }

        var details: [String: Value] = [
            "deletionState": .string(state.rawValue),
            "operationCommitState": .string(state.operationCommitState),
            "outcomeUnknown": .bool(state == .commitUnknown),
            "retrySafe": .bool(state == .rejected),
            "mutationAttempted": .bool(true),
            "targetId": .string(targetID),
            targetField: .string(targetID),
            "cause": structuredDeletionError(error),
            "inspection": inspection
        ]
        if state == .committedUnverified {
            details["operationCommitted"] = .bool(true)
            details["inspectionRequired"] = .bool(true)
        }

        return MCPResult.error(
            message,
            details: .object(details)
        )
    }

    func deletionFailureState(_ error: Error) -> AppLifecycleDeletionFailureState {
        guard let error = error as? ASCError else {
            return .rejected
        }
        switch error {
        case .deleteCommittedUnverified:
            return .committedUnverified
        case .deleteOutcomeUnknown:
            return .commitUnknown
        case .network:
            return .rejected
        case .api(_, let statusCode), .apiResponse(_, let statusCode):
            return .rejected
        case .authentication, .configuration, .parsing:
            return .rejected
        }
    }

    func structuredDeletionError(_ error: Error) -> Value {
        if let error = error as? ASCError {
            return error.structuredValue
        }
        return .object([
            "type": .string("unexpected"),
            "message": .string(Redactor.redact(error.localizedDescription))
        ])
    }

    func nullableString(
        _ name: String,
        from arguments: [String: Value],
        allowedValues: Set<String>? = nil
    ) throws -> NullableAttributeValue? {
        guard let value = arguments[name] else {
            return nil
        }
        if value.isNull {
            return .null
        }
        guard let string = value.stringValue else {
            throw AppLifecycleArgumentError("\(name) must be a string or null")
        }
        if let allowedValues, !allowedValues.contains(string) {
            throw AppLifecycleArgumentError("\(name) must be null or one of: \(allowedValues.sorted().joined(separator: ", "))")
        }
        return .string(string)
    }

    func nullableBool(_ name: String, from arguments: [String: Value]) throws -> NullableAttributeValue? {
        guard let value = arguments[name] else {
            return nil
        }
        if value.isNull {
            return .null
        }
        guard let bool = value.boolValue else {
            throw AppLifecycleArgumentError("\(name) must be a boolean or null")
        }
        return .bool(bool)
    }

    func nullableAbsoluteURI(
        _ name: String,
        from arguments: [String: Value]
    ) throws -> NullableAttributeValue? {
        guard let value = arguments[name] else {
            return nil
        }
        if value.isNull {
            return .null
        }
        guard let string = value.stringValue else {
            throw AppLifecycleArgumentError("\(name) must be an absolute URI or null")
        }
        let schemePattern = "^[A-Za-z][A-Za-z0-9+.-]*$"
        guard !string.isEmpty,
              string.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: string),
              let scheme = components.scheme,
              scheme.range(of: schemePattern, options: .regularExpression) != nil,
              URL(string: string)?.scheme == scheme else {
            throw AppLifecycleArgumentError("\(name) must be an absolute URI or null")
        }
        return .string(string)
    }

    func pagingTotal(from meta: JSONValue) -> Int? {
        guard let paging = meta.objectValue?["paging"]?.objectValue,
              case .int(let total)? = paging["total"] else {
            return nil
        }
        return total
    }

    static let platforms: Set<String> = ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]
    static let phasedReleaseCreateStates: Set<String> = ["INACTIVE", "ACTIVE", "PAUSED"]
    static let phasedReleaseUpdateStates: Set<String> = ["ACTIVE", "PAUSED", "COMPLETE"]
    static let appStoreStates: Set<String> = [
        "ACCEPTED",
        "DEVELOPER_REMOVED_FROM_SALE",
        "DEVELOPER_REJECTED",
        "IN_REVIEW",
        "INVALID_BINARY",
        "METADATA_REJECTED",
        "PENDING_APPLE_RELEASE",
        "PENDING_CONTRACT",
        "PENDING_DEVELOPER_RELEASE",
        "PREPARE_FOR_SUBMISSION",
        "PREORDER_READY_FOR_SALE",
        "PROCESSING_FOR_APP_STORE",
        "READY_FOR_REVIEW",
        "READY_FOR_SALE",
        "REJECTED",
        "REMOVED_FROM_SALE",
        "WAITING_FOR_EXPORT_COMPLIANCE",
        "WAITING_FOR_REVIEW",
        "REPLACED_WITH_NEW_VERSION",
        "NOT_APPLICABLE"
    ]
    static let appVersionStates: Set<String> = [
        "ACCEPTED",
        "DEVELOPER_REJECTED",
        "IN_REVIEW",
        "INVALID_BINARY",
        "METADATA_REJECTED",
        "PENDING_APPLE_RELEASE",
        "PENDING_DEVELOPER_RELEASE",
        "PREPARE_FOR_SUBMISSION",
        "PROCESSING_FOR_DISTRIBUTION",
        "READY_FOR_DISTRIBUTION",
        "READY_FOR_REVIEW",
        "REJECTED",
        "REPLACED_WITH_NEW_VERSION",
        "WAITING_FOR_EXPORT_COMPLIANCE",
        "WAITING_FOR_REVIEW"
    ]
}

private struct ReviewDetailAttributes {
    let contactFirstName: NullableAttributeValue?
    let contactLastName: NullableAttributeValue?
    let contactPhone: NullableAttributeValue?
    let contactEmail: NullableAttributeValue?
    let demoAccountName: NullableAttributeValue?
    let demoAccountPassword: NullableAttributeValue?
    let demoAccountRequired: NullableAttributeValue?
    let notes: NullableAttributeValue?
}

private struct AppLifecycleArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
