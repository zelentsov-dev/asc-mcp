import Foundation
import MCP

// MARK: - Tool Handlers
extension AppLifecycleWorker {

    /// Creates a new app version for release
    /// - Returns: JSON with created version details including ID, version string, platform and state
    /// - Throws: CallTool.Result with error if required parameters missing or API call fails
    func createVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue,
              let platform = arguments["platform"]?.stringValue,
              let versionString = arguments["version_string"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters missing: app_id, platform, version_string")],
                isError: true
            )
        }

        do {
            let releaseType = arguments["release_type"]?.stringValue ?? "MANUAL"
            let earliestDate = arguments["earliest_release_date"]?.stringValue

            let request = CreateAppStoreVersionRequest(
                platform: platform,
                versionString: versionString,
                releaseType: releaseType,
                earliestReleaseDate: earliestDate,
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create version: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let responseData: Data

            // Check for pagination URL
            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                responseData = try await httpClient.get(parsed.path, parameters: parsed.parameters)
            } else {
                var queryParams: [String: String] = [
                    "include": "build,appStoreVersionSubmission,appStoreVersionPhasedRelease"
                ]

                // Add state filter
                if let states = arguments["states"]?.arrayValue {
                    let stateStrings = states.compactMap { $0.stringValue }
                    if !stateStrings.isEmpty {
                        queryParams["filter[appVersionState]"] = stateStrings.joined(separator: ",")
                    }
                }

                // Add platform filter
                if let platform = arguments["platform"]?.stringValue {
                    queryParams["filter[platform]"] = platform
                }

                // Add limit
                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                responseData = try await httpClient.get(
                    "/v1/apps/\(appId)/appStoreVersions",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list versions: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            let queryParams: [String: String] = [
                "include": "build,appStoreVersionSubmission,appStoreVersionPhasedRelease,appStoreReviewDetail,ageRatingDeclaration"
            ]

            let response = try await httpClient.get(
                "/v1/appStoreVersions/\(versionId)",
                parameters: queryParams,
                as: PassthroughAPIResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "version": response.data.asAny
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get version: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            let releaseType = arguments["release_type"]?.stringValue
            let earliestDate = arguments["earliest_release_date"]?.stringValue
            let copyright = arguments["copyright"]?.stringValue
            let versionString = arguments["version_string"]?.stringValue

            guard releaseType != nil || earliestDate != nil || copyright != nil || versionString != nil else {
                return CallTool.Result(
                    content: [.text("Error: No attributes to update")],
                    isError: true
                )
            }

            let request = UpdateAppStoreVersionRequest(
                id: versionId,
                releaseType: releaseType,
                earliestReleaseDate: earliestDate,
                copyright: copyright,
                versionString: versionString
            )

            let response = try await httpClient.patch(
                "/v1/appStoreVersions/\(versionId)",
                body: request,
                as: ASCAppStoreVersionResponse.self
            )

            let v = response.data
            let result: [String: Any] = [
                "success": true,
                "version": [
                    "id": v.id,
                    "version_string": v.attributes?.versionString.jsonSafe ?? NSNull(),
                    "state": v.attributes?.appStoreState.jsonSafe ?? NSNull(),
                    "release_type": v.attributes?.releaseType.jsonSafe ?? NSNull(),
                    "created_date": v.attributes?.createdDate.jsonSafe ?? NSNull()
                ] as [String: Any],
                "message": "Version updated successfully"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update version: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameters missing: version_id, build_id")],
                isError: true
            )
        }

        do {
            let request = AttachBuildRequest(buildId: buildId)

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.patch(
                "/v1/appStoreVersions/\(versionId)/relationships/build",
                body: bodyData
            )

            let result: [String: Any] = [
                "success": true,
                "message": "Build \(buildId) attached to version \(versionId) successfully"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to attach build: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            // Resolve app ID: use provided app_id or extract from version
            let appId: String
            if let providedAppId = arguments["app_id"]?.stringValue {
                appId = providedAppId
            } else {
                // Fetch version to get the app relationship
                let versionResponse = try await httpClient.get(
                    "/v1/appStoreVersions/\(versionId)",
                    parameters: [:],
                    as: ASCAppStoreVersionResponse.self
                )
                guard let appData = versionResponse.data.relationships?.app?.data,
                      case .single(let appRef) = appData else {
                    return CallTool.Result(
                        content: [.text("Error: Could not resolve app ID from version. Provide 'app_id' explicitly.")],
                        isError: true
                    )
                }
                appId = appRef.id
            }

            let platform = arguments["platform"]?.stringValue ?? "IOS"

            // Step 1: Create review submission
            let submissionRequest = CreateReviewSubmissionRequest(platform: platform, appId: appId)
            let submissionResponse = try await httpClient.post(
                "/v1/reviewSubmissions",
                body: submissionRequest,
                as: SingleResourceResponse.self
            )
            let submissionId = submissionResponse.data.id

            // Step 2: Add version as review submission item
            let itemRequest = CreateReviewSubmissionItemRequest(submissionId: submissionId, versionId: versionId)
            let itemBodyData = try JSONEncoder().encode(itemRequest)
            _ = try await httpClient.post("/v1/reviewSubmissionItems", body: itemBodyData)

            // Step 3: Confirm the submission
            let confirmRequest = ConfirmReviewSubmissionRequest(submissionId: submissionId)
            let confirmResponse = try await httpClient.patch(
                "/v1/reviewSubmissions/\(submissionId)",
                body: confirmRequest,
                as: PassthroughAPIResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "submission": confirmResponse.data.asAny,
                "submission_id": submissionId,
                "message": "Version submitted for review successfully"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to submit for review: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Cancels an ongoing App Store review submission using the Review Submissions API
    /// - Returns: JSON with cancellation confirmation and submission details
    /// - Throws: CallTool.Result with error if review_submission_id missing or cancellation fails
    func cancelReview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let submissionId = arguments["review_submission_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'review_submission_id' is missing")],
                isError: true
            )
        }

        do {
            let request = CancelReviewSubmissionRequest(submissionId: submissionId)
            let response = try await httpClient.patch(
                "/v1/reviewSubmissions/\(submissionId)",
                body: request,
                as: PassthroughAPIResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "submission": response.data.asAny,
                "message": "Review submission cancelled successfully"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to cancel review: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'version_id' is missing")],
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create phased release: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            let response = try await httpClient.get(
                "/v1/appStoreVersions/\(versionId)/appStoreVersionPhasedRelease",
                parameters: [:],
                as: PassthroughAPIResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "phased_release": response.data.asAny
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get phased release: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameters missing: phased_release_id, phased_release_state")],
                isError: true
            )
        }

        do {
            let request = UpdatePhasedReleaseRequest(phasedReleaseId: phasedReleaseId, state: state)
            let response = try await httpClient.patch(
                "/v1/appStoreVersionPhasedReleases/\(phasedReleaseId)",
                body: request,
                as: PassthroughAPIResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "phased_release": response.data.asAny,
                "message": "Phased release state updated to \(state)"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update phased release: \(error.localizedDescription)")],
                isError: true
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
                content: [.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            let request = CreateReleaseRequest(versionId: versionId)
            let response = try await httpClient.post(
                "/v1/appStoreVersionReleaseRequests",
                body: request,
                as: PassthroughAPIResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "release_request": response.data.asAny,
                "message": "Version released to App Store successfully"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to release version: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Sets or updates review details for App Store reviewers including contact info and demo account
    /// - Returns: JSON with review details and action taken (created/updated)
    /// - Throws: CallTool.Result with error if version_id missing or API call fails
    func setReviewDetails(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionId = arguments["version_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            // First, check if review details already exist for this version
            let versionResponse = try await httpClient.get(
                "/v1/appStoreVersions/\(versionId)",
                parameters: ["include": "appStoreReviewDetail"],
                as: SingleResourceResponse.self
            )

            var existingReviewDetailId: String? = nil

            // Check if review detail relationship exists in relationships
            if case .object(let relationships) = versionResponse.data.relationships,
               case .object(let reviewDetail) = relationships["appStoreReviewDetail"],
               case .object(let reviewData) = reviewDetail["data"],
               case .string(let reviewId) = reviewData["id"] {
                existingReviewDetailId = reviewId
            }

            let attrs = ReviewDetailAttributes(
                contactFirstName: arguments["contact_first_name"]?.stringValue,
                contactLastName: arguments["contact_last_name"]?.stringValue,
                contactPhone: arguments["contact_phone"]?.stringValue,
                contactEmail: arguments["contact_email"]?.stringValue,
                demoAccountName: arguments["demo_account_name"]?.stringValue,
                demoAccountPassword: arguments["demo_account_password"]?.stringValue,
                demoAccountRequired: arguments["demo_account_required"]?.boolValue,
                notes: arguments["notes"]?.stringValue,
                attachmentAssetId: arguments["attachment_file_id"]?.stringValue
            )

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
                        notes: attrs.notes,
                        attachmentAssetId: attrs.attachmentAssetId
                    )
                )
                let bodyData = try JSONEncoder().encode(request)
                responseData = try await httpClient.patch(
                    "/v1/appStoreReviewDetails/\(reviewDetailId)",
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
                        notes: attrs.notes,
                        attachmentAssetId: attrs.attachmentAssetId
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to set review details: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates or creates age rating declaration for the app version
    /// - Returns: JSON with age rating details and action taken (created/updated)
    /// - Throws: CallTool.Result with error if version_id missing or API call fails
    func updateAgeRating(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionId = arguments["version_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            // First, check if age rating declaration already exists for this version
            let versionResponse = try await httpClient.get(
                "/v1/appStoreVersions/\(versionId)",
                parameters: ["include": "ageRatingDeclaration"],
                as: SingleResourceResponse.self
            )

            var existingAgeRatingId: String? = nil

            // Check if age rating declaration relationship exists
            if case .object(let relationships) = versionResponse.data.relationships,
               case .object(let ageRating) = relationships["ageRatingDeclaration"],
               case .object(let ageRatingData) = ageRating["data"],
               case .string(let ageRatingId) = ageRatingData["id"] {
                existingAgeRatingId = ageRatingId
            }

            // Map string enum age rating attributes (NONE/INFREQUENT_OR_MILD/FREQUENT_OR_INTENSE)
            let stringFields: [String: String] = [
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
                "guns_or_other_weapons": "gunsOrOtherWeapons",
                "kids_age_band": "kidsAgeBand",
                "age_rating_override": "ageRatingOverrideV2",
                "korea_age_rating_override": "koreaAgeRatingOverride"
            ]

            // Map boolean age rating attributes
            let boolFields: [String: String] = [
                "gambling": "gambling",
                "unrestricted_web_access": "unrestrictedWebAccess",
                "advertising": "advertising",
                "age_assurance": "ageAssurance",
                "health_or_wellness_topics": "healthOrWellnessTopics",
                "loot_box": "lootBox",
                "messaging_and_chat": "messagingAndChat",
                "parental_controls": "parentalControls",
                "user_generated_content": "userGeneratedContent"
            ]

            // Map string (URI) fields
            let uriFields: [String: String] = [
                "developer_age_rating_info_url": "developerAgeRatingInfoUrl"
            ]

            var attributes: [String: AgeRatingValue] = [:]

            for (argName, apiName) in stringFields {
                if let value = arguments[argName],
                   let stringValue = value.stringValue {
                    attributes[apiName] = .string(stringValue)
                }
            }

            for (argName, apiName) in boolFields {
                if let value = arguments[argName],
                   let boolValue = value.boolValue {
                    attributes[apiName] = .bool(boolValue)
                }
            }

            for (argName, apiName) in uriFields {
                if let value = arguments[argName],
                   let stringValue = value.stringValue {
                    attributes[apiName] = .string(stringValue)
                }
            }

            if attributes.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: No age rating attributes to update")],
                    isError: true
                )
            }

            let response: PassthroughAPIResponse
            let message: String

            if let ageRatingId = existingAgeRatingId {
                // Age rating exists - update it with PATCH
                let request = UpdateAgeRatingDeclarationRequest(
                    ageRatingId: ageRatingId,
                    attributes: attributes
                )
                response = try await httpClient.patch(
                    "/v1/ageRatingDeclarations/\(ageRatingId)",
                    body: request,
                    as: PassthroughAPIResponse.self
                )
                message = "Age rating declaration updated successfully"
            } else {
                // Age rating doesn't exist - create new with POST
                let request = CreateAgeRatingDeclarationRequest(
                    versionId: versionId,
                    attributes: attributes
                )
                response = try await httpClient.post(
                    "/v1/ageRatingDeclarations",
                    body: request,
                    as: PassthroughAPIResponse.self
                )
                message = "Age rating declaration created successfully"
            }

            let result: [String: Any] = [
                "success": true,
                "age_rating": response.data.asAny,
                "message": message,
                "action": existingAgeRatingId != nil ? "updated" : "created"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update age rating: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes an app store version (only PREPARE_FOR_SUBMISSION state)
    /// - Returns: JSON with success confirmation
    /// - Throws: CallTool.Result with error if version_id missing or API call fails
    func deleteVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionId = arguments["version_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appStoreVersions/\(versionId)")

            let result: [String: Any] = [
                "success": true,
                "message": "Version '\(versionId)' deleted successfully"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete version: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
}

// MARK: - Private Helpers

private struct ReviewDetailAttributes {
    let contactFirstName: String?
    let contactLastName: String?
    let contactPhone: String?
    let contactEmail: String?
    let demoAccountName: String?
    let demoAccountPassword: String?
    let demoAccountRequired: Bool?
    let notes: String?
    let attachmentAssetId: String?
}
