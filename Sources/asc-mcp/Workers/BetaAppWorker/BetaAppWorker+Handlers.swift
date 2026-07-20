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
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        let effectiveLimit: Int
        do {
            effectiveLimit = try boundedListLimit(arguments["limit"])
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        do {
            let response: ASCBetaAppLocalizationsResponse
            let queryParams = [
                "fields[betaAppLocalizations]": Self.localizationFields,
                "limit": String(effectiveLimit)
            ]

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: "/v1/apps/\(try ASCPathSegment.encode(appId))/betaAppLocalizations",
                        requiredParameters: queryParams,
                        allowedParameters: Set(queryParams.keys).union(["cursor"]),
                        requiredNonEmptyParameters: ["cursor"]
                    ),
                    as: ASCBetaAppLocalizationsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/apps/\(try ASCPathSegment.encode(appId))/betaAppLocalizations",
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
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list beta app localizations: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a beta app localization for an app
    /// - Returns: JSON with created localization details
    func createLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: app_id, locale")],
                isError: true
            )
        }

        let appId: String
        let locale: String
        let feedbackEmail: String?
        let marketingURL: String?
        let privacyPolicyURL: String?
        let tvOSPrivacyPolicy: String?
        let description: String?
        do {
            appId = try requiredString("app_id", from: arguments)
            locale = try requiredString("locale", from: arguments)
            feedbackEmail = try strictOptionalString("feedback_email", from: arguments)
            marketingURL = try strictOptionalString("marketing_url", from: arguments)
            privacyPolicyURL = try strictOptionalString("privacy_policy_url", from: arguments)
            tvOSPrivacyPolicy = try strictOptionalString("tv_os_privacy_policy", from: arguments)
            description = try strictOptionalString("description", from: arguments)
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        do {
            let request = CreateBetaAppLocalizationRequest(
                data: CreateBetaAppLocalizationRequest.CreateData(
                    attributes: CreateBetaAppLocalizationRequest.Attributes(
                        locale: locale,
                        feedbackEmail: feedbackEmail,
                        marketingUrl: marketingURL,
                        privacyPolicyUrl: privacyPolicyURL,
                        tvOsPrivacyPolicy: tvOSPrivacyPolicy,
                        description: description
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create beta app localization: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBetaAppLocalizationResponse = try await httpClient.get(
                "/v1/betaAppLocalizations/\(try ASCPathSegment.encode(localizationId))",
                parameters: ["fields[betaAppLocalizations]": Self.localizationFields],
                as: ASCBetaAppLocalizationResponse.self
            )

            let localization = formatBetaAppLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get beta app localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a beta app localization
    /// - Returns: JSON with updated localization details
    func updateLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        let localizationId: String
        let feedbackEmail: String?
        let marketingURL: String?
        let privacyPolicyURL: String?
        let tvOSPrivacyPolicy: String?
        let description: String?
        do {
            localizationId = try requiredString("localization_id", from: arguments)
            feedbackEmail = try strictOptionalString("feedback_email", from: arguments)
            marketingURL = try strictOptionalString("marketing_url", from: arguments)
            privacyPolicyURL = try strictOptionalString("privacy_policy_url", from: arguments)
            tvOSPrivacyPolicy = try strictOptionalString("tv_os_privacy_policy", from: arguments)
            description = try strictOptionalString("description", from: arguments)
        } catch {
            return MCPResult.error(error.localizedDescription)
        }
        guard [feedbackEmail, marketingURL, privacyPolicyURL, tvOSPrivacyPolicy, description].contains(where: { $0 != nil }) else {
            return MCPResult.error("At least one localization update field is required")
        }

        do {
            let request = UpdateBetaAppLocalizationRequest(
                data: UpdateBetaAppLocalizationRequest.UpdateData(
                    id: localizationId,
                    attributes: UpdateBetaAppLocalizationRequest.Attributes(
                        feedbackEmail: feedbackEmail,
                        marketingUrl: marketingURL,
                        privacyPolicyUrl: privacyPolicyURL,
                        tvOsPrivacyPolicy: tvOSPrivacyPolicy,
                        description: description
                    )
                )
            )

            let response: ASCBetaAppLocalizationResponse = try await httpClient.patch(
                "/v1/betaAppLocalizations/\(try ASCPathSegment.encode(localizationId))",
                body: request,
                as: ASCBetaAppLocalizationResponse.self
            )

            let localization = formatBetaAppLocalization(response.data)

            let result = [
                "success": true,
                "localization": localization
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to update beta app localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a beta app localization
    /// - Returns: JSON confirmation
    func deleteLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        let localizationId: String
        do {
            localizationId = try requiredString("localization_id", from: arguments)
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        do {
            _ = try await httpClient.delete("/v1/betaAppLocalizations/\(try ASCPathSegment.encode(localizationId))")

            let result = [
                "success": true,
                "message": "Beta app localization '\(localizationId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to delete beta app localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Beta App Review Submissions

    /// Submits a build for external beta review
    /// - Returns: JSON with submission details
    func submitForReview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        let buildId: String
        do {
            buildId = try requiredString("build_id", from: arguments)
        } catch {
            return MCPResult.error(error.localizedDescription)
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

            let resolution = try await resolveBuild(
                for: response.data,
                requestFallbackBuildID: buildId,
                allowedBuildIDs: [buildId]
            )
            let submission = formatBetaReviewSubmission(response.data, resolution: resolution)

            let result = [
                "success": true,
                "submission": submission
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to submit build for beta review: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists beta app review submissions
    /// - Returns: JSON array of submissions with review states
    func listSubmissions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildValue = arguments["build_id"] else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }

        let buildIDs: [String]
        let reviewStates: [String]?
        let effectiveLimit: Int
        do {
            buildIDs = try stringList(buildValue, field: "build_id")
            if let reviewStateValue = arguments["review_state"] {
                reviewStates = try stringList(
                    reviewStateValue,
                    field: "review_state",
                    allowedValues: Self.betaReviewStates
                )
            } else {
                reviewStates = nil
            }
            effectiveLimit = try boundedListLimit(arguments["limit"])
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        do {
            let response: ASCBetaAppReviewSubmissionsResponse
            var queryParams: [String: String] = [
                "filter[build]": buildIDs.joined(separator: ","),
                "fields[betaAppReviewSubmissions]": Self.reviewSubmissionFields,
                "fields[builds]": Self.includedBuildFields,
                "include": "build",
                "limit": String(effectiveLimit)
            ]

            if let reviewStates {
                queryParams["filter[betaReviewState]"] = reviewStates.joined(separator: ",")
            }

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: "/v1/betaAppReviewSubmissions",
                        requiredParameters: queryParams,
                        allowedParameters: Set(queryParams.keys).union(["cursor"]),
                        requiredNonEmptyParameters: ["cursor"]
                    ),
                    as: ASCBetaAppReviewSubmissionsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/betaAppReviewSubmissions",
                    parameters: queryParams,
                    as: ASCBetaAppReviewSubmissionsResponse.self
                )
            }

            let soleIncludedBuildID = response.data.count == 1 && response.included?.count == 1 && response.included?.first?.type == "builds"
                ? response.included?.first?.id
                : nil
            let includedFallbackBuildID = soleIncludedBuildID.flatMap { buildIDs.contains($0) ? $0 : nil }
            let filterFallbackBuildID = buildIDs.count == 1 ? buildIDs[0] : nil
            let allowedBuildIDs = Set(buildIDs)
            var submissions: [[String: Any]] = []
            for submission in response.data {
                let resolution = try await resolveBuild(
                    for: submission,
                    includedFallbackBuildID: includedFallbackBuildID,
                    filterFallbackBuildID: filterFallbackBuildID,
                    allowedBuildIDs: allowedBuildIDs
                )
                submissions.append(formatBetaReviewSubmission(submission, resolution: resolution))
            }

            var result: [String: Any] = [
                "success": true,
                "submissions": submissions,
                "count": submissions.count
            ]
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            if let next = response.links?.next {
                result["next_url"] = next
            }
            appendIncludedBuilds(response.included, to: &result)

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list beta app review submissions: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'submission_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBetaAppReviewSubmissionResponse = try await httpClient.get(
                "/v1/betaAppReviewSubmissions/\(try ASCPathSegment.encode(submissionId))",
                parameters: [
                    "fields[betaAppReviewSubmissions]": Self.reviewSubmissionFields,
                    "fields[builds]": Self.includedBuildFields,
                    "include": "build"
                ],
                as: ASCBetaAppReviewSubmissionResponse.self
            )

            let includedFallbackBuildID = response.included?.count == 1 && response.included?.first?.type == "builds"
                ? response.included?.first?.id
                : nil
            let resolution = try await resolveBuild(
                for: response.data,
                includedFallbackBuildID: includedFallbackBuildID
            )
            let submission = formatBetaReviewSubmission(response.data, resolution: resolution)

            var result = [
                "success": true,
                "submission": submission
            ] as [String: Any]
            appendIncludedBuilds(response.included, to: &result)

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get beta app review submission: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBetaAppReviewDetailResponse = try await httpClient.get(
                "/v1/apps/\(try ASCPathSegment.encode(appId))/betaAppReviewDetail",
                parameters: ["fields[betaAppReviewDetails]": Self.reviewDetailFields],
                as: ASCBetaAppReviewDetailResponse.self
            )

            let detail = formatBetaReviewDetail(response.data)

            let result = [
                "success": true,
                "review_detail": detail
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get beta app review details: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates beta app review details
    /// - Returns: JSON with updated review detail
    func updateReviewDetails(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'review_detail_id' is missing")],
                isError: true
            )
        }

        let reviewDetailId: String
        var attributes: [String: JSONValue] = [:]
        do {
            reviewDetailId = try requiredString("review_detail_id", from: arguments)
            let stringFields = [
                "contact_first_name": "contactFirstName",
                "contact_last_name": "contactLastName",
                "contact_phone": "contactPhone",
                "contact_email": "contactEmail",
                "demo_account_name": "demoAccountName",
                "demo_account_password": "demoAccountPassword",
                "notes": "notes"
            ]
            for (toolField, appleField) in stringFields {
                if let value = try nullableString(toolField, from: arguments) {
                    attributes[appleField] = value
                }
            }
            if let value = try nullableBool("demo_account_required", from: arguments) {
                attributes["demoAccountRequired"] = value
            }
        } catch {
            return MCPResult.error(error.localizedDescription)
        }
        guard !attributes.isEmpty else {
            return MCPResult.error("At least one review detail update field is required")
        }

        do {
            let request = UpdateBetaAppReviewDetailRequest(
                data: UpdateBetaAppReviewDetailRequest.UpdateData(
                    id: reviewDetailId,
                    attributes: attributes
                )
            )

            let response: ASCBetaAppReviewDetailResponse = try await httpClient.patch(
                "/v1/betaAppReviewDetails/\(try ASCPathSegment.encode(reviewDetailId))",
                body: request,
                as: ASCBetaAppReviewDetailResponse.self
            )

            let detail = formatBetaReviewDetail(response.data)

            let result = [
                "success": true,
                "review_detail": detail
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to update beta app review details: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatBetaAppLocalization(_ localization: ASCBetaAppLocalization) -> [String: Any] {
        return [
            "id": localization.id,
            "type": localization.type,
            "locale": (localization.attributes?.locale).jsonSafe,
            "feedbackEmail": (localization.attributes?.feedbackEmail).jsonSafe,
            "marketingUrl": (localization.attributes?.marketingUrl).jsonSafe,
            "privacyPolicyUrl": (localization.attributes?.privacyPolicyUrl).jsonSafe,
            "tvOsPrivacyPolicy": (localization.attributes?.tvOsPrivacyPolicy).jsonSafe,
            "description": (localization.attributes?.description).jsonSafe,
            "selfURL": (localization.links?.`self`).jsonSafe
        ]
    }

    private func formatBetaReviewSubmission(
        _ submission: ASCBetaAppReviewSubmission,
        resolution: BetaAppBuildResolution
    ) -> [String: Any] {
        let relationshipBuildID = submission.relationships?.build?.data?.id

        var result: [String: Any] = [
            "id": submission.id,
            "type": submission.type,
            "betaReviewState": (submission.attributes?.betaReviewState).jsonSafe,
            "submittedDate": (submission.attributes?.submittedDate).jsonSafe,
            "buildId": resolution.id,
            "buildIdSource": resolution.source,
            "relationshipBuildId": relationshipBuildID.jsonSafe,
            "buildRelatedURL": (submission.relationships?.build?.links?.related).jsonSafe,
            "selfURL": (submission.links?.`self`).jsonSafe
        ]
        if let relationshipFallbackID = resolution.relationshipFallbackID {
            result["relationshipFallbackBuildId"] = relationshipFallbackID
        }
        return result
    }

    private func resolveBuild(
        for submission: ASCBetaAppReviewSubmission,
        includedFallbackBuildID: String? = nil,
        requestFallbackBuildID: String? = nil,
        filterFallbackBuildID: String? = nil,
        allowedBuildIDs: Set<String>? = nil
    ) async throws -> BetaAppBuildResolution {
        if let relationship = submission.relationships?.build?.data {
            guard relationship.type == "builds", !relationship.id.isEmpty else {
                throw ASCError.parsing("Beta app review submission '\(submission.id)' returned invalid Build relationship linkage")
            }
            if let allowedBuildIDs, !allowedBuildIDs.contains(relationship.id) {
                throw ASCError.parsing("Beta app review submission '\(submission.id)' returned a Build outside the requested filter")
            }
            return BetaAppBuildResolution(
                id: relationship.id,
                source: "relationship",
                relationshipFallbackID: nil
            )
        }
        if let includedFallbackBuildID, !includedFallbackBuildID.isEmpty {
            return BetaAppBuildResolution(
                id: includedFallbackBuildID,
                source: "included",
                relationshipFallbackID: nil
            )
        }
        if let requestFallbackBuildID {
            return BetaAppBuildResolution(
                id: requestFallbackBuildID,
                source: "request",
                relationshipFallbackID: nil
            )
        }
        if let filterFallbackBuildID {
            return BetaAppBuildResolution(
                id: filterFallbackBuildID,
                source: "filter",
                relationshipFallbackID: nil
            )
        }

        let response: ASCBetaAppReviewSubmissionBuildLinkageResponse = try await httpClient.get(
            "/v1/betaAppReviewSubmissions/\(try ASCPathSegment.encode(submission.id))/relationships/build",
            as: ASCBetaAppReviewSubmissionBuildLinkageResponse.self
        )
        guard response.data.type == "builds", !response.data.id.isEmpty else {
            throw ASCError.parsing("Beta app review submission '\(submission.id)' returned invalid Build relationship linkage")
        }
        if let allowedBuildIDs, !allowedBuildIDs.contains(response.data.id) {
            throw ASCError.parsing("Beta app review submission '\(submission.id)' returned a Build outside the requested filter")
        }
        return BetaAppBuildResolution(
            id: response.data.id,
            source: "relationshipEndpoint",
            relationshipFallbackID: response.data.id
        )
    }

    private func appendIncludedBuilds(
        _ builds: [ASCBetaAppReviewIncludedBuild]?,
        to result: inout [String: Any]
    ) {
        guard let builds else {
            return
        }
        result["includedBuilds"] = builds.map { build in
            [
                "id": build.id,
                "type": build.type,
                "version": (build.attributes?.version).jsonSafe,
                "uploadedDate": (build.attributes?.uploadedDate).jsonSafe,
                "processingState": (build.attributes?.processingState).jsonSafe,
                "selfURL": (build.links?.`self`).jsonSafe
            ] as [String: Any]
        }
    }

    private func formatBetaReviewDetail(_ detail: ASCBetaAppReviewDetail) -> [String: Any] {
        var result: [String: Any] = [
            "id": detail.id,
            "type": detail.type,
            "contactFirstName": (detail.attributes?.contactFirstName).jsonSafe,
            "contactLastName": (detail.attributes?.contactLastName).jsonSafe,
            "contactPhone": (detail.attributes?.contactPhone).jsonSafe,
            "contactEmail": (detail.attributes?.contactEmail).jsonSafe,
            "demoAccountName": (detail.attributes?.demoAccountName).jsonSafe,
            "demoAccountRequired": (detail.attributes?.demoAccountRequired).jsonSafe,
            "notes": (detail.attributes?.notes).jsonSafe,
            "selfURL": (detail.links?.`self`).jsonSafe
        ]
        if detail.attributes?.demoAccountPassword != nil {
            result["demoAccountPassword"] = "[REDACTED]"
        }
        return result
    }

    private func strictOptionalString(_ name: String, from arguments: [String: Value]) throws -> String? {
        guard let value = arguments[name] else {
            return nil
        }
        guard !value.isNull, let string = value.stringValue else {
            throw BetaAppArgumentError("\(name) must be a string; omit the field instead of passing null")
        }
        return string
    }

    private func requiredString(_ name: String, from arguments: [String: Value]) throws -> String {
        guard let string = arguments[name]?.stringValue else {
            throw BetaAppArgumentError("\(name) must be a string")
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == string else {
            throw BetaAppArgumentError("\(name) must be a non-empty string without surrounding whitespace")
        }
        return string
    }

    private func nullableString(_ name: String, from arguments: [String: Value]) throws -> JSONValue? {
        guard let value = arguments[name] else {
            return nil
        }
        if value.isNull {
            return .null
        }
        guard let string = value.stringValue else {
            throw BetaAppArgumentError("\(name) must be a string or null")
        }
        return .string(string)
    }

    private func nullableBool(_ name: String, from arguments: [String: Value]) throws -> JSONValue? {
        guard let value = arguments[name] else {
            return nil
        }
        if value.isNull {
            return .null
        }
        guard let bool = value.boolValue else {
            throw BetaAppArgumentError("\(name) must be a boolean or null")
        }
        return .bool(bool)
    }

    private func stringList(
        _ value: Value,
        field: String,
        allowedValues: Set<String>? = nil
    ) throws -> [String] {
        let values: [String]
        if let string = value.stringValue {
            values = [string]
        } else if let array = value.arrayValue,
                  !array.isEmpty,
                  array.allSatisfy({ $0.stringValue != nil }) {
            values = array.compactMap(\.stringValue)
        } else {
            throw BetaAppArgumentError("\(field) must be a non-empty string or array of strings")
        }
        guard values.allSatisfy({ value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed == value
        }) else {
            throw BetaAppArgumentError("\(field) must contain only non-empty strings without surrounding whitespace")
        }
        guard values.allSatisfy({ !$0.contains(",") }) else {
            throw BetaAppArgumentError("\(field) values must not contain commas")
        }
        guard Set(values).count == values.count else {
            throw BetaAppArgumentError("\(field) must not contain duplicate values")
        }
        if let allowedValues,
           let invalid = values.first(where: { !allowedValues.contains($0) }) {
            throw BetaAppArgumentError("\(field) contains unsupported value '\(invalid)'")
        }
        return values
    }

    private func boundedListLimit(_ value: Value?) throws -> Int {
        guard let value else {
            return 25
        }
        guard let limit = value.intValue else {
            throw BetaAppArgumentError("limit must be an integer")
        }
        return min(max(limit, 1), 200)
    }

    private static let localizationFields = "feedbackEmail,marketingUrl,privacyPolicyUrl,tvOsPrivacyPolicy,description,locale"
    private static let reviewDetailFields = "contactFirstName,contactLastName,contactPhone,contactEmail,demoAccountName,demoAccountPassword,demoAccountRequired,notes"
    private static let reviewSubmissionFields = "betaReviewState,submittedDate,build"
    private static let includedBuildFields = "version,uploadedDate,processingState"

    private static let betaReviewStates: Set<String> = [
        "WAITING_FOR_REVIEW",
        "IN_REVIEW",
        "REJECTED",
        "APPROVED"
    ]
}

private struct BetaAppArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private struct BetaAppBuildResolution {
    let id: String
    let source: String
    let relationshipFallbackID: String?
}
