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

            let response = try await httpClient.post(
                "/v1/appStoreVersions",
                body: request,
                as: PassthroughAPIResponse.self
            )

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
            guard let versions = response.data.arrayValue else {
                throw AppLifecycleQueryArgumentError("Apple returned a non-array app version collection")
            }

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

            guard let ratings = response.data.arrayValue else {
                throw AppLifecycleQueryArgumentError("Apple returned a non-array territory age rating collection")
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

            let response = try await httpClient.patch(
                "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))",
                body: request,
                as: ASCAppStoreVersionResponse.self
            )

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
            guard let appData = versionResponse.data.relationships?.app?.data,
                  case .single(let appRef) = appData,
                  appRef.type == "apps" else {
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
            let submissionResponse = try await httpClient.post(
                "/v1/reviewSubmissions",
                body: submissionRequest,
                as: SingleResourceResponse.self
            )
            submissionId = submissionResponse.data.id

            // Step 2: Add version as review submission item
            failedStep = "create_review_submission_item"
            guard let createdSubmissionId = submissionId else {
                return MCPResult.error("Review submission was created without an ID.")
            }
            let itemRequest = CreateReviewSubmissionItemRequest(submissionId: createdSubmissionId, versionId: versionId)
            let itemBodyData = try JSONEncoder().encode(itemRequest)
            _ = try await httpClient.post("/v1/reviewSubmissionItems", body: itemBodyData)

            // Step 3: Confirm the submission
            failedStep = "confirm_review_submission"
            let confirmRequest = ConfirmReviewSubmissionRequest(submissionId: createdSubmissionId)
            let confirmResponse = try await httpClient.patch(
                "/v1/reviewSubmissions/\(try ASCPathSegment.encode(createdSubmissionId))",
                body: confirmRequest,
                as: PassthroughAPIResponse.self
            )

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
            let response = try await httpClient.patch(
                "/v1/reviewSubmissions/\(try ASCPathSegment.encode(submissionId))",
                body: request,
                as: PassthroughAPIResponse.self
            )

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
            let response = try await httpClient.post(
                "/v1/appStoreVersionPhasedReleases",
                body: request,
                as: PassthroughAPIResponse.self
            )

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
            let response = try await httpClient.patch(
                "/v1/appStoreVersionPhasedReleases/\(try ASCPathSegment.encode(phasedReleaseId))",
                body: request,
                as: PassthroughAPIResponse.self
            )

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

        do {
            _ = try await httpClient.delete(
                "/v1/appStoreVersionPhasedReleases/\(try ASCPathSegment.encode(phasedReleaseId))"
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
            let response = try await httpClient.post(
                "/v1/appStoreVersionReleaseRequests",
                body: request,
                as: PassthroughAPIResponse.self
            )

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

            let responseData: Data
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
                let bodyData = try JSONEncoder().encode(request)
                responseData = try await httpClient.patch(
                    "/v1/appStoreReviewDetails/\(try ASCPathSegment.encode(reviewDetailId))",
                    body: bodyData
                )
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
                let bodyData = try JSONEncoder().encode(request)
                responseData = try await httpClient.post(
                    "/v1/appStoreReviewDetails",
                    body: bodyData
                )
                message = "Review details created successfully"
            }

            let response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)

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

                guard let appRelationship = versionResponse.data.relationships?.app?.data,
                      case .single(let app) = appRelationship else {
                    return MCPResult.error("Could not resolve the owning app from version \(versionId). Provide app_info_id from app_info_list.")
                }

                guard appInfoState(for: versionResponse.data.attributes?.appVersionState) != nil else {
                    let versionState = versionResponse.data.attributes?.appVersionState ?? "UNKNOWN"
                    return MCPResult.error("Version state \(versionState) cannot be safely mapped to App Info. Provide app_info_id from app_info_list.")
                }

                let appInfos = try await httpClient.get(
                    "/v1/apps/\(try ASCPathSegment.encode(app.id))/appInfos",
                    parameters: [
                        "fields[appInfos]": "state",
                        "limit": "200"
                    ],
                    as: ASCAppInfosResponse.self
                )

                guard let appInfo = selectAppInfo(
                    from: appInfos.data,
                    versionState: versionResponse.data.attributes?.appVersionState
                ) else {
                    let candidates = appInfos.data.map { info in
                        "\(info.id):\(info.attributes?.state ?? "UNKNOWN")"
                    }.joined(separator: ", ")
                    return MCPResult.error("Could not safely select App Info for version \(versionId). Provide app_info_id from app_info_list. Candidates: \(candidates.isEmpty ? "none" : candidates).")
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
            let ageRatingId = ageRatingResponse.data.id

            let request = UpdateAgeRatingDeclarationRequest(
                ageRatingId: ageRatingId,
                attributes: attributes
            )
            let response = try await httpClient.patch(
                "/v1/ageRatingDeclarations/\(try ASCPathSegment.encode(ageRatingId))",
                body: request,
                as: PassthroughAPIResponse.self
            )

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

        do {
            _ = try await httpClient.delete("/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))")

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

// MARK: - Private Helpers

private extension AppLifecycleWorker {
    func resolveReviewDetailId(versionId: String) async throws -> String? {
        do {
            let response = try await httpClient.get(
                "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))/appStoreReviewDetail",
                parameters: [:],
                as: SingleResourceResponse.self
            )
            return response.data.id
        } catch let error as ASCError {
            switch error {
            case .api(_, 404), .apiResponse(_, 404):
                _ = try await httpClient.get(
                    "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))",
                    parameters: ["fields[appStoreVersions]": "versionString"],
                    as: ASCAppStoreVersionResponse.self
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
        let outcomeUnknown = isAmbiguousDeletionFailure(error)
        let state = outcomeUnknown ? "commit_unknown" : "rejected"
        let message = outcomeUnknown
            ? "The \(resourceName) delete outcome is unknown. Do not retry until the exact target is inspected."
            : "Failed to delete \(resourceName): \(error.localizedDescription)"

        return MCPResult.error(
            message,
            details: .object([
                "deletionState": .string(state),
                "operationCommitState": .string(outcomeUnknown ? "unknown" : "rejected"),
                "outcomeUnknown": .bool(outcomeUnknown),
                "retrySafe": .bool(!outcomeUnknown),
                "mutationAttempted": .bool(true),
                "targetId": .string(targetID),
                targetField: .string(targetID),
                "cause": structuredDeletionError(error),
                "inspection": inspection
            ])
        )
    }

    func isAmbiguousDeletionFailure(_ error: Error) -> Bool {
        guard let error = error as? ASCError else {
            return true
        }
        switch error {
        case .network:
            return true
        case .api(_, let statusCode), .apiResponse(_, let statusCode):
            return statusCode == 408 || (500...599).contains(statusCode)
        case .authentication, .configuration, .parsing:
            return false
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
