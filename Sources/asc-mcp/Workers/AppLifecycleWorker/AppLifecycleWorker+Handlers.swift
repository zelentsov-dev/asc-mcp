import Foundation
import MCP

// MARK: - Tool Handlers
extension AppLifecycleWorker {

    private func versionFilterValue(_ name: String, from arguments: [String: Value]) throws -> String? {
        guard let value = arguments[name] else {
            return nil
        }
        guard let items = value.arrayValue, !items.isEmpty else {
            throw AppLifecycleQueryArgumentError("\(name) must be a non-empty array of strings")
        }
        let strings = try items.map { item in
            guard let string = item.stringValue,
                  !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppLifecycleQueryArgumentError("\(name) must contain only non-empty strings")
            }
            return string
        }
        return strings.joined(separator: ",")
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
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        let effectiveLimit = min(max(arguments["limit"]?.intValue ?? 25, 1), 200)

        do {
            let responseData: Data

            // Check for pagination URL
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                var requiredParameters: [String: String] = [
                    "include": "build,appStoreVersionSubmission,appStoreVersionPhasedRelease"
                ]
                if let states = arguments["states"]?.arrayValue {
                    let stateStrings = states.compactMap { $0.stringValue }
                    if !stateStrings.isEmpty {
                        requiredParameters["filter[appStoreState]"] = stateStrings.joined(separator: ",")
                    }
                }
                if let states = arguments["app_version_states"]?.arrayValue {
                    let stateStrings = states.compactMap { $0.stringValue }
                    if !stateStrings.isEmpty {
                        requiredParameters["filter[appVersionState]"] = stateStrings.joined(separator: ",")
                    }
                }
                if let platform = arguments["platform"]?.stringValue {
                    requiredParameters["filter[platform]"] = platform
                }
                if let versionIDs = try versionFilterValue("version_ids", from: arguments) {
                    requiredParameters["filter[id]"] = versionIDs
                }
                if let versionStrings = try versionFilterValue("version_strings", from: arguments) {
                    requiredParameters["filter[versionString]"] = versionStrings
                }
                requiredParameters["limit"] = String(effectiveLimit)
                responseData = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: "/v1/apps/\(try ASCPathSegment.encode(appId))/appStoreVersions",
                        requiredParameters: requiredParameters
                    )
                )
            } else {
                var queryParams: [String: String] = [
                    "include": "build,appStoreVersionSubmission,appStoreVersionPhasedRelease"
                ]

                // Add state filter
                if let states = arguments["states"]?.arrayValue {
                    let stateStrings = states.compactMap { $0.stringValue }
                    if !stateStrings.isEmpty {
                        queryParams["filter[appStoreState]"] = stateStrings.joined(separator: ",")
                    }
                }

                if let states = arguments["app_version_states"]?.arrayValue {
                    let stateStrings = states.compactMap { $0.stringValue }
                    if !stateStrings.isEmpty {
                        queryParams["filter[appVersionState]"] = stateStrings.joined(separator: ",")
                    }
                }

                // Add platform filter
                if let platform = arguments["platform"]?.stringValue {
                    queryParams["filter[platform]"] = platform
                }
                if let versionIDs = try versionFilterValue("version_ids", from: arguments) {
                    queryParams["filter[id]"] = versionIDs
                }
                if let versionStrings = try versionFilterValue("version_strings", from: arguments) {
                    queryParams["filter[versionString]"] = versionStrings
                }

                queryParams["limit"] = String(effectiveLimit)

                responseData = try await httpClient.get(
                    "/v1/apps/\(try ASCPathSegment.encode(appId))/appStoreVersions",
                    parameters: queryParams
                )
            }

            let response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)

            var result: [String: Any] = [
                "success": true,
                "versions": response.data.asAny,
                "app_id": appId
            ]

            // Extract next_url from links
            if case .object(let linksObj) = response.links,
               case .string(let nextUrl) = linksObj["next"] {
                result["next_url"] = nextUrl
            }

            if let included = response.included {
                result["included"] = included.map { $0.asAny }
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
                "include": "build,appStoreVersionSubmission,appStoreVersionPhasedRelease,appStoreReviewDetail"
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
                    "version_string": (v.attributes?.versionString).jsonSafe,
                    "state": (v.attributes?.appVersionState ?? v.attributes?.appStoreState).jsonSafe,
                    "appVersionState": (v.attributes?.appVersionState).jsonSafe,
                    "appStoreState": (v.attributes?.appStoreState).jsonSafe,
                    "app_version_state": (v.attributes?.appVersionState).jsonSafe,
                    "app_store_state": (v.attributes?.appStoreState).jsonSafe,
                    "release_type": (v.attributes?.releaseType).jsonSafe,
                    "review_type": (v.attributes?.reviewType).jsonSafe,
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
        guard let arguments = params.arguments,
              let versionId = arguments["version_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            let state = arguments["phased_release_state"]?.stringValue ?? "INACTIVE"

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
        guard let arguments = params.arguments,
              let phasedReleaseId = arguments["phased_release_id"]?.stringValue,
              let state = arguments["phased_release_state"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters missing: phased_release_id, phased_release_state")],
                isError: true
            )
        }

        do {
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

    func deletePhasedRelease(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let phasedReleaseId = arguments["phased_release_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'phased_release_id' is missing")
        }

        do {
            _ = try await httpClient.delete(
                "/v1/appStoreVersionPhasedReleases/\(try ASCPathSegment.encode(phasedReleaseId))"
            )
            return MCPResult.jsonObject([
                "success": true,
                "phased_release_id": phasedReleaseId,
                "message": "Phased release deleted successfully"
            ])
        } catch {
            return MCPResult.error("Failed to delete phased release: \(error.localizedDescription)")
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
            if let value = try nullableString("developer_age_rating_info_url", from: arguments) {
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

    /// Deletes an app store version when Apple marks it deletable
    /// - Returns: JSON with success confirmation
    /// - Throws: CallTool.Result with error if version_id missing or API call fails
    func deleteVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionId = arguments["version_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))")

            let result: [String: Any] = [
                "success": true,
                "message": "Version '\(versionId)' deleted successfully"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to delete version: \(error.localizedDescription)")],
                isError: true
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
