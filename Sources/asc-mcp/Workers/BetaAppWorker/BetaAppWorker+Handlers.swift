import Foundation
import MCP

// MARK: - Tool Handlers
extension BetaAppWorker {

    // MARK: - Beta App Localizations

    /// Lists beta app localizations for an app
    /// - Returns: JSON array of localizations with TestFlight metadata per locale
    func listLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBetaAppLocalizationsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCBetaAppLocalizationsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/apps/\(appId)/betaAppLocalizations",
                    parameters: queryParams,
                    as: ASCBetaAppLocalizationsResponse.self
                )
            }

            let localizations = response.data.map { formatBetaAppLocalization($0) }

            var result: [String: Any] = [
                "success": true,
                "localizations": localizations,
                "count": localizations.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list beta app localizations: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a beta app localization for an app
    /// - Returns: JSON with created localization details
    func createLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue,
              let locale = arguments["locale"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: app_id, locale")],
                isError: true
            )
        }

        do {
            let request = CreateBetaAppLocalizationRequest(
                data: CreateBetaAppLocalizationRequest.CreateData(
                    attributes: CreateBetaAppLocalizationRequest.Attributes(
                        locale: locale,
                        feedbackEmail: arguments["feedback_email"]?.stringValue,
                        marketingUrl: arguments["marketing_url"]?.stringValue,
                        privacyPolicyUrl: arguments["privacy_policy_url"]?.stringValue,
                        tvOsPrivacyPolicy: arguments["tv_os_privacy_policy"]?.stringValue,
                        description: arguments["description"]?.stringValue
                    ),
                    relationships: CreateBetaAppLocalizationRequest.Relationships(
                        app: CreateBetaAppLocalizationRequest.AppRelationship(
                            data: ASCResourceIdentifier(type: "apps", id: appId)
                        )
                    )
                )
            )

            let response: ASCBetaAppLocalizationResponse = try await httpClient.post(
                "/v1/betaAppLocalizations",
                body: request,
                as: ASCBetaAppLocalizationResponse.self
            )

            let localization = formatBetaAppLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create beta app localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets a specific beta app localization by ID
    /// - Returns: JSON with localization details
    func getLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let localizationId = arguments["localization_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBetaAppLocalizationResponse = try await httpClient.get(
                "/v1/betaAppLocalizations/\(localizationId)",
                parameters: [:],
                as: ASCBetaAppLocalizationResponse.self
            )

            let localization = formatBetaAppLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get beta app localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a beta app localization
    /// - Returns: JSON with updated localization details
    func updateLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let localizationId = arguments["localization_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateBetaAppLocalizationRequest(
                data: UpdateBetaAppLocalizationRequest.UpdateData(
                    id: localizationId,
                    attributes: UpdateBetaAppLocalizationRequest.Attributes(
                        feedbackEmail: arguments["feedback_email"]?.stringValue,
                        marketingUrl: arguments["marketing_url"]?.stringValue,
                        privacyPolicyUrl: arguments["privacy_policy_url"]?.stringValue,
                        tvOsPrivacyPolicy: arguments["tv_os_privacy_policy"]?.stringValue,
                        description: arguments["description"]?.stringValue
                    )
                )
            )

            let response: ASCBetaAppLocalizationResponse = try await httpClient.patch(
                "/v1/betaAppLocalizations/\(localizationId)",
                body: request,
                as: ASCBetaAppLocalizationResponse.self
            )

            let localization = formatBetaAppLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update beta app localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a beta app localization
    /// - Returns: JSON confirmation
    func deleteLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let localizationId = arguments["localization_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/betaAppLocalizations/\(localizationId)")

            let result = [
                "success": true,
                "message": "Beta app localization '\(localizationId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete beta app localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Beta App Review Submissions

    /// Submits a build for external beta review
    /// - Returns: JSON with submission details
    func submitForReview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildId = arguments["build_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        do {
            let request = CreateBetaAppReviewSubmissionRequest(
                data: CreateBetaAppReviewSubmissionRequest.CreateData(
                    relationships: CreateBetaAppReviewSubmissionRequest.Relationships(
                        build: CreateBetaAppReviewSubmissionRequest.BuildRelationship(
                            data: ASCResourceIdentifier(type: "builds", id: buildId)
                        )
                    )
                )
            )

            let response: ASCBetaAppReviewSubmissionResponse = try await httpClient.post(
                "/v1/betaAppReviewSubmissions",
                body: request,
                as: ASCBetaAppReviewSubmissionResponse.self
            )

            let submission = formatBetaReviewSubmission(response.data)

            let result = [
                "success": true,
                "submission": submission
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to submit build for beta review: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists beta app review submissions
    /// - Returns: JSON array of submissions with review states
    func listSubmissions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildId = arguments["build_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBetaAppReviewSubmissionsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCBetaAppReviewSubmissionsResponse.self)
            } else {
                var queryParams: [String: String] = [
                    "filter[build]": buildId
                ]

                if let reviewState = arguments["review_state"]?.stringValue {
                    queryParams["filter[betaReviewState]"] = reviewState
                }
                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/betaAppReviewSubmissions",
                    parameters: queryParams,
                    as: ASCBetaAppReviewSubmissionsResponse.self
                )
            }

            let submissions = response.data.map { formatBetaReviewSubmission($0) }

            var result: [String: Any] = [
                "success": true,
                "submissions": submissions,
                "count": submissions.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list beta app review submissions: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets a specific beta app review submission by ID
    /// - Returns: JSON with submission details
    func getSubmission(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let submissionId = arguments["submission_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'submission_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBetaAppReviewSubmissionResponse = try await httpClient.get(
                "/v1/betaAppReviewSubmissions/\(submissionId)",
                parameters: [:],
                as: ASCBetaAppReviewSubmissionResponse.self
            )

            let submission = formatBetaReviewSubmission(response.data)

            let result = [
                "success": true,
                "submission": submission
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get beta app review submission: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Beta App Review Details

    /// Gets beta app review details for an app
    /// - Returns: JSON with review detail (demo account, contact info)
    func getReviewDetails(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBetaAppReviewDetailResponse = try await httpClient.get(
                "/v1/apps/\(appId)/betaAppReviewDetail",
                parameters: [:],
                as: ASCBetaAppReviewDetailResponse.self
            )

            let detail = formatBetaReviewDetail(response.data)

            let result = [
                "success": true,
                "review_detail": detail
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get beta app review details: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates beta app review details
    /// - Returns: JSON with updated review detail
    func updateReviewDetails(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let reviewDetailId = arguments["review_detail_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'review_detail_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateBetaAppReviewDetailRequest(
                data: UpdateBetaAppReviewDetailRequest.UpdateData(
                    id: reviewDetailId,
                    attributes: UpdateBetaAppReviewDetailRequest.Attributes(
                        contactFirstName: arguments["contact_first_name"]?.stringValue,
                        contactLastName: arguments["contact_last_name"]?.stringValue,
                        contactPhone: arguments["contact_phone"]?.stringValue,
                        contactEmail: arguments["contact_email"]?.stringValue,
                        demoAccountName: arguments["demo_account_name"]?.stringValue,
                        demoAccountPassword: arguments["demo_account_password"]?.stringValue,
                        demoAccountRequired: arguments["demo_account_required"]?.boolValue,
                        notes: arguments["notes"]?.stringValue
                    )
                )
            )

            let response: ASCBetaAppReviewDetailResponse = try await httpClient.patch(
                "/v1/betaAppReviewDetails/\(reviewDetailId)",
                body: request,
                as: ASCBetaAppReviewDetailResponse.self
            )

            let detail = formatBetaReviewDetail(response.data)

            let result = [
                "success": true,
                "review_detail": detail
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update beta app review details: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatBetaAppLocalization(_ localization: ASCBetaAppLocalization) -> [String: Any] {
        return [
            "id": localization.id,
            "type": localization.type,
            "locale": localization.attributes.locale.jsonSafe,
            "feedbackEmail": localization.attributes.feedbackEmail.jsonSafe,
            "marketingUrl": localization.attributes.marketingUrl.jsonSafe,
            "privacyPolicyUrl": localization.attributes.privacyPolicyUrl.jsonSafe,
            "tvOsPrivacyPolicy": localization.attributes.tvOsPrivacyPolicy.jsonSafe,
            "description": localization.attributes.description.jsonSafe
        ]
    }

    private func formatBetaReviewSubmission(_ submission: ASCBetaAppReviewSubmission) -> [String: Any] {
        return [
            "id": submission.id,
            "type": submission.type,
            "betaReviewState": submission.attributes.betaReviewState.jsonSafe,
            "submittedDate": submission.attributes.submittedDate.jsonSafe
        ]
    }

    private func formatBetaReviewDetail(_ detail: ASCBetaAppReviewDetail) -> [String: Any] {
        return [
            "id": detail.id,
            "type": detail.type,
            "contactFirstName": detail.attributes.contactFirstName.jsonSafe,
            "contactLastName": detail.attributes.contactLastName.jsonSafe,
            "contactPhone": detail.attributes.contactPhone.jsonSafe,
            "contactEmail": detail.attributes.contactEmail.jsonSafe,
            "demoAccountName": detail.attributes.demoAccountName.jsonSafe,
            "demoAccountPassword": detail.attributes.demoAccountPassword.jsonSafe,
            "demoAccountRequired": detail.attributes.demoAccountRequired.jsonSafe,
            "notes": detail.attributes.notes.jsonSafe
        ]
    }
}
