import Foundation
import MCP

extension ReviewSubmissionsWorker {
    static let submissionIncludes = [
        "app",
        "items",
        "appStoreVersionForReview",
        "submittedByActor",
        "lastUpdatedByActor"
    ]

    private static let submissionFields =
        "platform,submittedDate,state,app,items,appStoreVersionForReview,submittedByActor,lastUpdatedByActor"
    private static let appFields = "name,bundleId,sku,primaryLocale"
    private static let actorFields = "actorType,userFirstName,userLastName,userEmail,apiKeyId"
    private static let appStoreVersionFields =
        "platform,versionString,appStoreState,appVersionState,reviewType,releaseType,createdDate"
    private static let itemIdentityFields = [
        "state",
        "appStoreVersion",
        "appCustomProductPageVersion",
        "appStoreVersionExperiment",
        "appStoreVersionExperimentV2",
        "appEvent",
        "backgroundAssetVersion",
        "gameCenterAchievementVersion",
        "gameCenterActivityVersion",
        "gameCenterChallengeVersion",
        "gameCenterLeaderboardSetVersion",
        "gameCenterLeaderboardVersion",
        "inAppPurchaseVersion",
        "subscriptionVersion",
        "subscriptionGroupVersion"
    ].joined(separator: ",")
    private static let supportedItemIncludes = [
        "appStoreVersion",
        "appCustomProductPageVersion",
        "appStoreVersionExperimentV2",
        "appEvent",
        "backgroundAssetVersion",
        "inAppPurchaseVersion",
        "subscriptionVersion",
        "subscriptionGroupVersion"
    ]
    private static let submissionIncludedTypes: Set<String> = [
        "actors",
        "apps",
        "appStoreVersions",
        "reviewSubmissionItems"
    ]
    private static let itemResourceTypes: [String: String] = [
        "appStoreVersion": "appStoreVersions",
        "appCustomProductPageVersion": "appCustomProductPageVersions",
        "appStoreVersionExperiment": "appStoreVersionExperiments",
        "appStoreVersionExperimentV2": "appStoreVersionExperiments",
        "appEvent": "appEvents",
        "backgroundAssetVersion": "backgroundAssetVersions",
        "gameCenterAchievementVersion": "gameCenterAchievementVersions",
        "gameCenterActivityVersion": "gameCenterActivityVersions",
        "gameCenterChallengeVersion": "gameCenterChallengeVersions",
        "gameCenterLeaderboardSetVersion": "gameCenterLeaderboardSetVersions",
        "gameCenterLeaderboardVersion": "gameCenterLeaderboardVersions",
        "inAppPurchaseVersion": "inAppPurchaseVersions",
        "subscriptionVersion": "subscriptionVersions",
        "subscriptionGroupVersion": "subscriptionGroupVersions"
    ]

    private static let itemRelationFields: [(String, ASCReviewSubmissionItemRelation)] = [
        ("app_store_version_id", .appStoreVersion),
        ("app_custom_product_page_version_id", .appCustomProductPageVersion),
        ("app_store_version_experiment_v2_id", .appStoreVersionExperimentV2),
        ("app_event_id", .appEvent),
        ("background_asset_version_id", .backgroundAssetVersion),
        ("in_app_purchase_version_id", .inAppPurchaseVersion),
        ("subscription_version_id", .subscriptionVersion),
        ("subscription_group_version_id", .subscriptionGroupVersion)
    ]

    /// Lists review submissions for one app using Apple's required ownership filter.
    /// - Parameter params: Tool parameters containing `app_id` and optional filters/pagination.
    /// - Returns: Submission projections, included recovery context, count, total, and next URL.
    /// - Throws: App Store Connect transport or decoding errors.
    func listSubmissions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'app_id' is missing")
        }

        do {
            let appID = try requiredCanonicalIdentifier("app_id", from: arguments)
            let states = try stringList(
                arguments["states"],
                field: "states",
                allowedValues: Set(ASCReviewSubmissionState.allCases.map(\.rawValue))
            )
            let platforms = try stringList(
                arguments["platforms"],
                field: "platforms",
                allowedValues: Set(ASCReviewSubmissionPlatform.allCases.map(\.rawValue))
            )
            let includes = try stringList(
                arguments["include"],
                field: "include",
                allowedValues: Set(Self.submissionIncludes)
            ) ?? Self.submissionIncludes
            let limit = try boundedInteger(arguments["limit"], field: "limit", maximum: 200, defaultValue: 25)
            let itemLimit = try boundedInteger(
                arguments["item_limit"],
                field: "item_limit",
                maximum: 50,
                defaultValue: 50
            )
            let path = "/v1/reviewSubmissions"
            var query = submissionQuery(includes: includes, itemLimit: itemLimit)
            query["filter[app]"] = appID
            query["limit"] = String(limit)
            if let states {
                query["filter[state]"] = states.joined(separator: ",")
            }
            if let platforms {
                query["filter[platform]"] = platforms.joined(separator: ",")
            }

            let response: ASCReviewSubmissionsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: strictPaginationScope(path: path, query: query),
                    as: ASCReviewSubmissionsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    path,
                    parameters: query,
                    as: ASCReviewSubmissionsResponse.self
                )
            }
            try validateDocumentSelf(
                response.links.`self`,
                expectedPath: path,
                context: "review submissions list"
            )
            try validateSubmissions(response.data, expectedAppID: appID)
            try validatePagingInformation(
                response.meta,
                pageCount: response.data.count,
                context: "review submissions list"
            )
            try validateCursorNextConsistency(
                response.meta,
                nextURL: response.links.next,
                context: "review submissions list"
            )
            try validateIncludedResources(
                response.included,
                allowedTypes: Self.submissionIncludedTypes,
                context: "review submissions list"
            )

            var result: [String: Any] = [
                "success": true,
                "app_id": appID,
                "submissions": response.data.map(formatSubmission),
                "count": response.data.count
            ]
            appendPaging(links: response.links, meta: response.meta, to: &result)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list review submissions")
        }
    }

    /// Gets one review submission with the relationships needed to resume a partial workflow.
    /// - Parameter params: Tool parameters containing `submission_id` and optional include controls.
    /// - Returns: A normalized submission and included resource projections.
    /// - Throws: App Store Connect transport or decoding errors.
    func getSubmission(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'submission_id' is missing")
        }

        do {
            let submissionID = try requiredCanonicalIdentifier("submission_id", from: arguments)
            let includes = try stringList(
                arguments["include"],
                field: "include",
                allowedValues: Set(Self.submissionIncludes)
            ) ?? Self.submissionIncludes
            let itemLimit = try boundedInteger(
                arguments["item_limit"],
                field: "item_limit",
                maximum: 50,
                defaultValue: 50
            )
            let response = try await httpClient.get(
                "/v1/reviewSubmissions/\(try ASCPathSegment.encode(submissionID))",
                parameters: submissionQuery(includes: includes, itemLimit: itemLimit),
                as: ASCReviewSubmissionResponse.self
            )
            try validateSubmission(
                response.data,
                expectedID: submissionID,
                expectedAppID: nil,
                requiresExpectedApp: false,
                context: "review submission get"
            )
            try validateDocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/reviewSubmissions/\(try ASCPathSegment.encode(submissionID))",
                context: "review submission get"
            )
            try validateIncludedResources(
                response.included,
                allowedTypes: Self.submissionIncludedTypes,
                context: "review submission get"
            )

            var result: [String: Any] = [
                "success": true,
                "submission": formatSubmission(response.data)
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to get review submission")
        }
    }

    /// Creates an empty review submission for one app.
    /// - Parameter params: Tool parameters containing `app_id` and optional nullable `platform`.
    /// - Returns: The created submission and deterministic recovery tool references.
    /// - Throws: App Store Connect transport, encoding, or decoding errors.
    func createSubmission(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'app_id' is missing")
        }

        let appID: String
        let platform: ASCReviewSubmissionNullablePlatform?
        do {
            appID = try requiredCanonicalIdentifier("app_id", from: arguments)
            platform = try nullablePlatform(arguments["platform"], field: "platform")
        } catch {
            return MCPResult.error(error, prefix: "Failed to create review submission")
        }

        var identifiers = ["app_id": Value.string(appID)]
        identifiers["platform"] = arguments["platform"]
        let inspection = submissionListInspection(
            appID: appID,
            requestedPlatform: arguments["platform"]
        )
        let body: Data
        do {
            body = try encodeMutationBody(
                ASCReviewSubmissionCreateRequest(appID: appID, platform: platform)
            )
        } catch {
            return preRequestEncodingFailure(
                operation: "create",
                error: error,
                identifiers: identifiers
            )
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/reviewSubmissions", body: body)
        } catch {
            return mutationRequestFailure(
                operation: "create",
                error: error,
                identifiers: identifiers,
                inspection: inspection
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Review submission create"
            )
            let response = try decodeMutationResponse(
                receipt.data,
                as: ASCReviewSubmissionResponse.self
            )
            try validateSubmission(
                response.data,
                expectedID: nil,
                expectedAppID: appID,
                requiresExpectedApp: false,
                context: "review submission create"
            )
            try validateDocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/reviewSubmissions/\(try ASCPathSegment.encode(response.data.id))",
                context: "review submission create"
            )
            try validateIncludedResources(
                response.included,
                allowedTypes: Self.submissionIncludedTypes,
                context: "review submission create"
            )
            var result: [String: Any] = [
                "success": true,
                "submission": formatSubmission(response.data)
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return committedUnverifiedMutationFailure(
                operation: "create",
                reason: error,
                identifiers: identifiers,
                inspection: inspection
            )
        }
    }

    /// Lists every typed item in a review submission, including scoped relationships this worker cannot add.
    /// - Parameter params: Tool parameters containing `submission_id` and optional pagination.
    /// - Returns: Item projections, included resources, count, total, and next URL.
    /// - Throws: App Store Connect transport or decoding errors.
    func listItems(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'submission_id' is missing")
        }

        do {
            let submissionID = try requiredCanonicalIdentifier("submission_id", from: arguments)
            let limit = try boundedInteger(arguments["limit"], field: "limit", maximum: 200, defaultValue: 25)
            let path = "/v1/reviewSubmissions/\(try ASCPathSegment.encode(submissionID))/items"
            var query = itemListQuery()
            query["limit"] = String(limit)

            let response: ASCReviewSubmissionItemsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: strictPaginationScope(path: path, query: query),
                    as: ASCReviewSubmissionItemsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    path,
                    parameters: query,
                    as: ASCReviewSubmissionItemsResponse.self
                )
            }
            try validateDocumentSelf(
                response.links.`self`,
                expectedPath: path,
                context: "review submission items list"
            )
            try validateItems(response.data, context: "review submission items list")
            try validatePagingInformation(
                response.meta,
                pageCount: response.data.count,
                context: "review submission items list"
            )
            try validateCursorNextConsistency(
                response.meta,
                nextURL: response.links.next,
                context: "review submission items list"
            )
            try validateIncludedResources(
                response.included,
                allowedTypes: Set(Self.supportedItemIncludes.compactMap { Self.itemResourceTypes[$0] }),
                context: "review submission items list"
            )

            var result: [String: Any] = [
                "success": true,
                "submission_id": submissionID,
                "items": response.data.map { formatItem($0) },
                "count": response.data.count,
                "recovery": submissionRecovery(submissionID: submissionID)
            ]
            appendPaging(links: response.links, meta: response.meta, to: &result)
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list review submission items")
        }
    }

    /// Adds exactly one supported typed resource to a review submission.
    /// - Parameter params: Tool parameters containing `submission_id` and exactly one supported resource ID.
    /// - Returns: The created review item and recovery identifiers.
    /// - Throws: App Store Connect transport, encoding, or decoding errors.
    func addItem(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'submission_id' is missing")
        }

        let submissionID: String
        let selected: (relation: ASCReviewSubmissionItemRelation, resourceID: String)
        do {
            submissionID = try requiredCanonicalIdentifier("submission_id", from: arguments)
            try rejectScopedItemArguments(arguments)
            selected = try selectedItemRelation(from: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to add review submission item")
        }

        let identifiers: [String: Value] = [
            "submission_id": .string(submissionID),
            "resource_type": .string(selected.relation.rawValue),
            "resource_id": .string(selected.resourceID)
        ]
        let inspection = itemListInspection(
            submissionID: submissionID,
            itemID: nil,
            requestedRelation: selected
        )
        let body: Data
        do {
            body = try encodeMutationBody(ASCReviewSubmissionItemCreateRequest(
                submissionID: submissionID,
                relation: selected.relation,
                resourceID: selected.resourceID
            ))
        } catch {
            return preRequestEncodingFailure(
                operation: "add_item",
                error: error,
                identifiers: identifiers
            )
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/reviewSubmissionItems", body: body)
        } catch {
            return mutationRequestFailure(
                operation: "add_item",
                error: error,
                identifiers: identifiers,
                inspection: inspection
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Review submission item create"
            )
            let response = try decodeMutationResponse(
                receipt.data,
                as: ASCReviewSubmissionItemResponse.self
            )
            try validateCreatedItem(response.data, requested: selected)
            try validateDocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/reviewSubmissionItems/\(try ASCPathSegment.encode(response.data.id))",
                context: "review submission item create"
            )
            try validateIncludedResources(
                response.included,
                allowedTypes: [selected.relation.resourceType],
                context: "review submission item create"
            )
            var result: [String: Any] = [
                "success": true,
                "submission_id": submissionID,
                "item": formatItem(response.data),
                "recovery": itemRecovery(
                    submissionID: submissionID,
                    itemID: response.data.id
                )
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return committedUnverifiedMutationFailure(
                operation: "add_item",
                reason: error,
                identifiers: identifiers,
                inspection: inspection
            )
        }
    }

    /// Updates the nullable `resolved` and `removed` attributes of a review item.
    /// - Parameter params: Tool parameters containing `item_id` and at least one tri-state update.
    /// - Returns: The updated review item.
    /// - Throws: App Store Connect transport, encoding, or decoding errors.
    func updateItem(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters are missing: submission_id, item_id")
        }

        let submissionID: String
        let itemID: String
        let resolved: ASCReviewSubmissionNullableBool?
        let removed: ASCReviewSubmissionNullableBool?
        do {
            submissionID = try requiredCanonicalIdentifier("submission_id", from: arguments)
            itemID = try requiredCanonicalIdentifier("item_id", from: arguments)
            resolved = try nullableBool(arguments["resolved"], field: "resolved")
            removed = try nullableBool(arguments["removed"], field: "removed")
            guard resolved != nil || removed != nil else {
                throw ReviewSubmissionArgumentError("At least one update field is required: resolved or removed")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to update review submission item")
        }
        var retryArguments: [String: Value] = [
            "submission_id": .string(submissionID),
            "item_id": .string(itemID)
        ]
        retryArguments["resolved"] = arguments["resolved"]
        retryArguments["removed"] = arguments["removed"]

        do {
            try await verifyItemMembership(submissionID: submissionID, itemID: itemID)
        } catch {
            return membershipPreflightFailure(
                error: error,
                operation: "update_item",
                submissionID: submissionID,
                itemID: itemID
            )
        }

        var identifiers: [String: Value] = [
            "submission_id": .string(submissionID),
            "item_id": .string(itemID)
        ]
        identifiers["resolved"] = arguments["resolved"]
        identifiers["removed"] = arguments["removed"]
        let inspection = itemListInspection(
            submissionID: submissionID,
            itemID: itemID,
            requestedRelation: nil
        )
        let body: Data
        do {
            body = try encodeMutationBody(ASCReviewSubmissionItemUpdateRequest(
                itemID: itemID,
                resolved: resolved,
                removed: removed
            ))
        } catch {
            return preRequestEncodingFailure(
                operation: "update_item",
                error: error,
                identifiers: identifiers
            )
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(
                "/v1/reviewSubmissionItems/\(try ASCPathSegment.encode(itemID))",
                body: body
            )
        } catch {
            return mutationRequestFailure(
                operation: "update_item",
                error: error,
                identifiers: identifiers,
                inspection: inspection,
                retry: recoveryStep(
                    tool: "review_submissions_update_item",
                    arguments: retryArguments
                )
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 200,
                context: "Review submission item update"
            )
            let response = try decodeMutationResponse(
                receipt.data,
                as: ASCReviewSubmissionItemResponse.self
            )
            try validateItem(
                response.data,
                expectedID: itemID,
                context: "review submission item update"
            )
            try validateDocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/reviewSubmissionItems/\(try ASCPathSegment.encode(itemID))",
                context: "review submission item update"
            )
            try validateIncludedResources(
                response.included,
                allowedTypes: Set(Self.itemResourceTypes.values),
                context: "review submission item update"
            )
            var result: [String: Any] = [
                "success": true,
                "item": formatItem(response.data),
                "recovery": itemRecovery(submissionID: submissionID, itemID: response.data.id)
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return committedUnverifiedMutationFailure(
                operation: "update_item",
                reason: error,
                identifiers: identifiers,
                inspection: inspection
            )
        }
    }

    /// Deletes one review submission item.
    /// - Parameter params: Tool parameters containing the parent submission, item ID, and exact confirmation ID.
    /// - Returns: A local confirmation after Apple's empty 204 response.
    /// - Throws: App Store Connect transport errors.
    func removeItem(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters are missing: submission_id, item_id, confirm_item_id")
        }

        let submissionID: String
        let itemID: String
        do {
            submissionID = try requiredCanonicalIdentifier("submission_id", from: arguments)
            itemID = try requiredCanonicalIdentifier("item_id", from: arguments)
            let confirmationID = try requiredCanonicalIdentifier("confirm_item_id", from: arguments)
            guard confirmationID == itemID else {
                throw ReviewSubmissionArgumentError(
                    "Deleting a review submission item is irreversible. Set confirm_item_id to the exact item_id to continue."
                )
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to remove review submission item")
        }

        do {
            try await verifyItemMembership(submissionID: submissionID, itemID: itemID)
        } catch {
            return membershipPreflightFailure(
                error: error,
                operation: "remove_item",
                submissionID: submissionID,
                itemID: itemID
            )
        }

        do {
            _ = try await httpClient.delete(
                "/v1/reviewSubmissionItems/\(try ASCPathSegment.encode(itemID))"
            )
            return MCPResult.jsonObject([
                "success": true,
                "submission_id": submissionID,
                "item_id": itemID,
                "deletionState": "confirmed",
                "operationCommitState": "committed",
                "retrySafe": false,
                "message": "Review submission item '\(itemID)' removed"
            ])
        } catch {
            return deletionFailure(
                error: error,
                submissionID: submissionID,
                itemID: itemID
            )
        }
    }

    /// Submits an assembled review submission.
    /// - Parameter params: Tool parameters containing `submission_id`.
    /// - Returns: The updated submission and its recovery identifiers.
    /// - Throws: App Store Connect transport, encoding, or decoding errors.
    func submit(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        try await updateSubmissionTransition(
            params,
            action: "submit",
            request: { ASCReviewSubmissionUpdateRequest(
                submissionID: $0,
                submitted: .value(true)
            ) }
        )
    }

    /// Cancels a review submission.
    /// - Parameter params: Tool parameters containing `submission_id`.
    /// - Returns: The updated submission and its recovery identifiers.
    /// - Throws: App Store Connect transport, encoding, or decoding errors.
    func cancel(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        try await updateSubmissionTransition(
            params,
            action: "cancel",
            request: { ASCReviewSubmissionUpdateRequest(
                submissionID: $0,
                canceled: .value(true)
            ) }
        )
    }

    private func updateSubmissionTransition(
        _ params: CallTool.Parameters,
        action: String,
        request: (String) -> ASCReviewSubmissionUpdateRequest
    ) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'submission_id' is missing")
        }

        let submissionID: String
        do {
            submissionID = try requiredCanonicalIdentifier("submission_id", from: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to \(action) review submission")
        }

        let identifiers = ["submission_id": Value.string(submissionID)]
        let inspection = submissionInspection(submissionID: submissionID)
        let body: Data
        do {
            body = try encodeMutationBody(request(submissionID))
        } catch {
            return preRequestEncodingFailure(
                operation: action,
                error: error,
                identifiers: identifiers
            )
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(
                "/v1/reviewSubmissions/\(try ASCPathSegment.encode(submissionID))",
                body: body
            )
        } catch {
            return mutationRequestFailure(
                operation: action,
                error: error,
                identifiers: identifiers,
                inspection: inspection
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 200,
                context: "Review submission \(action)"
            )
            let response = try decodeMutationResponse(
                receipt.data,
                as: ASCReviewSubmissionResponse.self
            )
            try validateSubmission(
                response.data,
                expectedID: submissionID,
                expectedAppID: nil,
                requiresExpectedApp: false,
                context: "review submission \(action)"
            )
            try validateDocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/reviewSubmissions/\(try ASCPathSegment.encode(submissionID))",
                context: "review submission \(action)"
            )
            try validateIncludedResources(
                response.included,
                allowedTypes: Self.submissionIncludedTypes,
                context: "review submission \(action)"
            )
            var result: [String: Any] = [
                "success": true,
                "submission": formatSubmission(response.data)
            ]
            appendIncluded(response.included, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return committedUnverifiedMutationFailure(
                operation: action,
                reason: error,
                identifiers: identifiers,
                inspection: inspection
            )
        }
    }

    private func submissionQuery(includes: [String], itemLimit: Int) -> [String: String] {
        [
            "fields[reviewSubmissions]": Self.submissionFields,
            "fields[apps]": Self.appFields,
            "fields[reviewSubmissionItems]": Self.itemIdentityFields,
            "fields[appStoreVersions]": Self.appStoreVersionFields,
            "fields[actors]": Self.actorFields,
            "include": includes.joined(separator: ","),
            "limit[items]": String(itemLimit)
        ]
    }

    private func itemListQuery() -> [String: String] {
        [
            "fields[reviewSubmissionItems]": Self.itemIdentityFields,
            "fields[appStoreVersions]": Self.appStoreVersionFields,
            "fields[appCustomProductPageVersions]": "version,state,deepLink",
            "fields[appStoreVersionExperiments]": "name,trafficProportion,state,reviewRequired,startDate,endDate,platform",
            "fields[appEvents]": "referenceName,badge,eventState,deepLink,purchaseRequirement,primaryLocale,priority,purpose",
            "fields[backgroundAssetVersions]": "createdDate,platforms,state,stateDetails,version,locale",
            "fields[inAppPurchaseVersions]": "version,state",
            "fields[subscriptionVersions]": "version,state",
            "fields[subscriptionGroupVersions]": "version,state",
            "include": Self.supportedItemIncludes.joined(separator: ",")
        ]
    }

    private func strictPaginationScope(path: String, query: [String: String]) -> PaginationScope {
        PaginationScope(
            path: path,
            requiredParameters: query,
            allowedParameters: Set(query.keys).union(["cursor"]),
            requiredNonEmptyParameters: ["cursor"]
        )
    }

    private func verifyItemMembership(
        submissionID: String,
        itemID: String
    ) async throws {
        let path = "/v1/reviewSubmissions/\(try ASCPathSegment.encode(submissionID))/items"
        var query = itemListQuery()
        query["limit"] = "200"
        let scope = strictPaginationScope(path: path, query: query)
        var response = try await httpClient.get(
            path,
            parameters: query,
            as: ASCReviewSubmissionItemsResponse.self
        )
        var seenContinuationURLs = Set<String>()
        var seenItemIDs = Set<String>()
        var targetCount = 0
        var expectedTotal: Int?

        while true {
            try validateDocumentSelf(
                response.links.`self`,
                expectedPath: path,
                context: "review item membership preflight"
            )
            try validateItems(response.data, context: "review item membership preflight")
            try validatePagingInformation(
                response.meta,
                pageCount: response.data.count,
                context: "review item membership preflight"
            )
            try validateCursorNextConsistency(
                response.meta,
                nextURL: response.links.next,
                context: "review item membership preflight"
            )
            if let total = response.meta?.paging.total {
                if let expectedTotal, expectedTotal != total {
                    throw ASCError.parsing(
                        "Apple changed the review item total across membership pages"
                    )
                }
                expectedTotal = total
            }
            try validateIncludedResources(
                response.included,
                allowedTypes: Set(Self.supportedItemIncludes.compactMap { Self.itemResourceTypes[$0] }),
                context: "review item membership preflight"
            )
            for item in response.data {
                guard seenItemIDs.insert(item.id).inserted else {
                    throw ASCError.parsing(
                        "Apple returned duplicate review item identity '\(item.id)' across membership pages"
                    )
                }
                if item.id == itemID {
                    targetCount += 1
                }
            }
            if let expectedTotal, seenItemIDs.count > expectedTotal {
                throw ASCError.parsing(
                    "Apple returned more review item identities than its declared total"
                )
            }

            guard let nextURL = response.links.next else { break }
            guard seenContinuationURLs.insert(nextURL).inserted else {
                throw ASCError.parsing(
                    "Apple returned a repeated review item continuation URL during membership verification"
                )
            }
            response = try await httpClient.getPage(
                nextURL,
                scope: scope,
                as: ASCReviewSubmissionItemsResponse.self
            )
        }

        if let expectedTotal, expectedTotal != seenItemIDs.count {
            throw ASCError.parsing(
                "Apple returned an incomplete review item collection during membership verification"
            )
        }

        guard targetCount == 1 else {
            throw ASCError.parsing(
                "Review submission item '\(itemID)' was not found exactly once under submission '\(submissionID)'"
            )
        }
    }

    private func selectedItemRelation(
        from arguments: [String: Value]
    ) throws -> (relation: ASCReviewSubmissionItemRelation, resourceID: String) {
        var selected: [(ASCReviewSubmissionItemRelation, String)] = []
        for (field, relation) in Self.itemRelationFields where arguments[field] != nil {
            let resourceID = try requiredCanonicalIdentifier(field, from: arguments)
            selected.append((relation, resourceID))
        }
        guard selected.count == 1, let value = selected.first else {
            throw ReviewSubmissionArgumentError(
                "Exactly one supported item relation ID is required: \(Self.itemRelationFields.map(\.0).joined(separator: ", "))"
            )
        }
        return value
    }

    private func rejectScopedItemArguments(_ arguments: [String: Value]) throws {
        let scoped = arguments.keys.first { key in
            let normalized = key.lowercased().replacingOccurrences(of: "_", with: "")
            return normalized.contains("gamecenter")
        }
        if let scoped {
            throw ReviewSubmissionArgumentError(
                "'\(scoped)' is outside this worker; Game Center review items remain in the scoped Game Center product"
            )
        }
        if arguments["app_store_version_experiment_id"] != nil {
            throw ReviewSubmissionArgumentError(
                "Legacy appStoreVersionExperiment is not supported; use app_store_version_experiment_v2_id"
            )
        }
        for field in ["relation_type", "resource_type", "item_type"] {
            guard let value = arguments[field]?.stringValue else { continue }
            let normalized = value.lowercased().replacingOccurrences(of: "_", with: "")
            if normalized.contains("gamecenter") {
                throw ReviewSubmissionArgumentError(
                    "Game Center review items remain in the scoped Game Center product"
                )
            }
            if normalized == "appstoreversionexperiment" || normalized == "appstoreversionexperiments" {
                throw ReviewSubmissionArgumentError(
                    "Legacy appStoreVersionExperiment is not supported; use app_store_version_experiment_v2_id"
                )
            }
        }
    }

    private func stringList(
        _ value: Value?,
        field: String,
        allowedValues: Set<String>
    ) throws -> [String]? {
        guard let value else { return nil }

        let values: [String]
        if let string = value.stringValue {
            values = string
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else if let array = value.arrayValue {
            guard !array.isEmpty else {
                throw ReviewSubmissionArgumentError("'\(field)' must contain at least one value")
            }
            var parsed: [String] = []
            for item in array {
                guard let string = item.stringValue else {
                    throw ReviewSubmissionArgumentError("'\(field)' must contain only strings")
                }
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.contains(",") else {
                    throw ReviewSubmissionArgumentError(
                        "'\(field)' array values must not contain commas; use separate array elements"
                    )
                }
                parsed.append(trimmed)
            }
            values = parsed
        } else {
            throw ReviewSubmissionArgumentError("'\(field)' must be a string, CSV string, or array of strings")
        }

        guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
            throw ReviewSubmissionArgumentError("'\(field)' must contain only non-empty values")
        }
        guard Set(values).count == values.count else {
            throw ReviewSubmissionArgumentError("'\(field)' must not contain duplicate values")
        }
        if let invalid = values.first(where: { !allowedValues.contains($0) }) {
            throw ReviewSubmissionArgumentError(
                "Unsupported \(field) value '\(invalid)'. Valid values: \(allowedValues.sorted().joined(separator: ", "))"
            )
        }
        return values
    }

    private func boundedInteger(
        _ value: Value?,
        field: String,
        maximum: Int,
        defaultValue: Int
    ) throws -> Int {
        guard let value else { return defaultValue }
        guard let integer = value.intValue, (1...maximum).contains(integer) else {
            throw ReviewSubmissionArgumentError("'\(field)' must be an integer from 1 through \(maximum)")
        }
        return integer
    }

    private func nullablePlatform(
        _ value: Value?,
        field: String
    ) throws -> ASCReviewSubmissionNullablePlatform? {
        guard let value else { return nil }
        if value.isNull {
            return .null
        }
        guard let rawValue = value.stringValue,
              let platform = ASCReviewSubmissionPlatform(rawValue: rawValue) else {
            throw ReviewSubmissionArgumentError(
                "'\(field)' must be null or one of: \(ASCReviewSubmissionPlatform.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        return .value(platform)
    }

    private func nullableBool(
        _ value: Value?,
        field: String
    ) throws -> ASCReviewSubmissionNullableBool? {
        guard let value else { return nil }
        if value.isNull {
            return .null
        }
        guard let boolean = value.boolValue else {
            throw ReviewSubmissionArgumentError("'\(field)' must be a boolean or null")
        }
        return .value(boolean)
    }

    private func requiredCanonicalIdentifier(
        _ field: String,
        from arguments: [String: Value]
    ) throws -> String {
        guard let value = arguments[field] else {
            throw ReviewSubmissionArgumentError("Required parameter '\(field)' is missing")
        }
        guard let string = value.stringValue,
              !string.isEmpty,
              string == string.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ReviewSubmissionArgumentError("'\(field)' must be a non-empty canonical identifier")
        }
        _ = try ASCPathSegment.encode(string, field: field)
        return string
    }

    private func validateDocumentSelf(
        _ value: String,
        expectedPath: String,
        context: String
    ) throws {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ASCError.parsing("Apple returned an invalid required links.self in \(context)")
        }
        guard let components = URLComponents(string: value),
              components.fragment == nil,
              components.user == nil,
              components.password == nil else {
            throw ASCError.parsing("Apple returned an invalid required links.self URI in \(context)")
        }
        if components.scheme != nil || components.host != nil {
            guard components.scheme == "https",
                  let host = components.host,
                  !host.isEmpty else {
                throw ASCError.parsing("Apple returned a non-HTTPS required links.self URI in \(context)")
            }
        }
        guard components.percentEncodedPath == expectedPath else {
            throw ASCError.parsing("Apple returned a required links.self path outside \(context)")
        }
        _ = try validatedASCAPIEndpoint(components.percentEncodedPath)
    }

    private func validateSubmissions(
        _ submissions: [ASCReviewSubmission],
        expectedAppID: String
    ) throws {
        var identities = Set<String>()
        for submission in submissions {
            try validateSubmission(
                submission,
                expectedID: nil,
                expectedAppID: expectedAppID,
                requiresExpectedApp: true,
                context: "review submissions list"
            )
            guard identities.insert(submission.id).inserted else {
                throw ASCError.parsing("Apple returned duplicate review submission identity '\(submission.id)'")
            }
        }
    }

    private func validateSubmission(
        _ submission: ASCReviewSubmission,
        expectedID: String?,
        expectedAppID: String?,
        requiresExpectedApp: Bool,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: submission.type,
            id: submission.id,
            expectedType: "reviewSubmissions",
            expectedID: expectedID,
            context: context
        )
        if let selfURL = submission.links?.`self` {
            try validateDocumentSelf(
                selfURL,
                expectedPath: "/v1/reviewSubmissions/\(try ASCPathSegment.encode(submission.id))",
                context: "\(context) resource links"
            )
        }

        let relationships = submission.relationships
        try validatePagingInformation(
            relationships?.items?.meta,
            pageCount: relationships?.items?.data?.count ?? 0,
            context: "\(context) included items relationship"
        )
        if let nextCursor = relationships?.items?.meta?.paging.nextCursor,
           nextCursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ASCError.parsing(
                "Apple returned an empty paging cursor in \(context) included items relationship"
            )
        }
        if let expectedAppID {
            if requiresExpectedApp, relationships?.app?.data == nil {
                throw ASCError.parsing(
                    "Apple did not return the requested app relationship in \(context)"
                )
            }
            if let app = relationships?.app?.data {
                try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                    type: app.type,
                    id: app.id,
                    expectedType: "apps",
                    expectedID: expectedAppID,
                    context: "\(context) app relationship"
                )
            }
        } else if let app = relationships?.app?.data {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: app.type,
                id: app.id,
                expectedType: "apps",
                context: "\(context) app relationship"
            )
        }

        try validateOptionalRelationship(
            relationships?.appStoreVersionForReview?.data,
            expectedType: "appStoreVersions",
            context: "\(context) appStoreVersionForReview relationship"
        )
        try validateOptionalRelationship(
            relationships?.submittedByActor?.data,
            expectedType: "actors",
            context: "\(context) submittedByActor relationship"
        )
        try validateOptionalRelationship(
            relationships?.lastUpdatedByActor?.data,
            expectedType: "actors",
            context: "\(context) lastUpdatedByActor relationship"
        )

        var itemIDs = Set<String>()
        for item in relationships?.items?.data ?? [] {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: item.type,
                id: item.id,
                expectedType: "reviewSubmissionItems",
                context: "\(context) items relationship"
            )
            guard itemIDs.insert(item.id).inserted else {
                throw ASCError.parsing("Apple returned duplicate review item identity '\(item.id)' in \(context)")
            }
        }
    }

    private func validateOptionalRelationship(
        _ identifier: ASCResourceIdentifier?,
        expectedType: String,
        context: String
    ) throws {
        guard let identifier else { return }
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: identifier.type,
            id: identifier.id,
            expectedType: expectedType,
            context: context
        )
    }

    private func validateItems(
        _ items: [ASCReviewSubmissionItem],
        context: String
    ) throws {
        var identities = Set<String>()
        for item in items {
            try validateItem(item, expectedID: nil, context: context)
            guard identities.insert(item.id).inserted else {
                throw ASCError.parsing("Apple returned duplicate review item identity '\(item.id)' in \(context)")
            }
        }
    }

    private func validateItem(
        _ item: ASCReviewSubmissionItem,
        expectedID: String?,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: item.type,
            id: item.id,
            expectedType: "reviewSubmissionItems",
            expectedID: expectedID,
            context: context
        )
        if let selfURL = item.links?.`self` {
            try validateDocumentSelf(
                selfURL,
                expectedPath: "/v1/reviewSubmissionItems/\(try ASCPathSegment.encode(item.id))",
                context: "\(context) resource links"
            )
        }
        for relation in itemRelations(item.relationships) {
            guard let expectedType = Self.itemResourceTypes[relation.name] else {
                throw ASCError.parsing("Apple returned unknown review item relationship '\(relation.name)' in \(context)")
            }
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: relation.identifier.type,
                id: relation.identifier.id,
                expectedType: expectedType,
                context: "\(context) \(relation.name) relationship"
            )
        }
    }

    private func validateIncludedResources(
        _ resources: [ASCReviewSubmissionIncludedResource]?,
        allowedTypes: Set<String>,
        context: String
    ) throws {
        var identities = Set<String>()
        for resource in resources ?? [] {
            guard allowedTypes.contains(resource.type) else {
                throw ASCError.parsing(
                    "Apple returned unexpected included resource type '\(resource.type)' in \(context)"
                )
            }
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: resource.type,
                id: resource.id,
                expectedType: resource.type,
                context: "\(context) included resources"
            )
            guard identities.insert("\(resource.type):\(resource.id)").inserted else {
                throw ASCError.parsing(
                    "Apple returned duplicate included resource '\(resource.type):\(resource.id)' in \(context)"
                )
            }
        }
    }

    private func validatePagingInformation(
        _ meta: ASCReviewSubmissionPagingInformation?,
        pageCount: Int,
        context: String
    ) throws {
        guard let paging = meta?.paging else { return }
        guard paging.limit > 0 else {
            throw ASCError.parsing("Apple returned a non-positive paging limit in \(context)")
        }
        guard paging.limit >= pageCount else {
            throw ASCError.parsing("Apple returned paging limit below the page count in \(context)")
        }
        if let total = paging.total, total < pageCount {
            throw ASCError.parsing("Apple returned paging total below the page count in \(context)")
        }
    }

    private func validateCursorNextConsistency(
        _ meta: ASCReviewSubmissionPagingInformation?,
        nextURL: String?,
        context: String
    ) throws {
        guard let cursor = meta?.paging.nextCursor else { return }
        guard !cursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ASCError.parsing("Apple returned an empty paging cursor in \(context)")
        }
        guard nextURL != nil else {
            throw ASCError.parsing("Apple returned a paging cursor without links.next in \(context)")
        }
    }

    private func formatSubmission(_ submission: ASCReviewSubmission) -> [String: Any] {
        let relationships = submission.relationships
        let includedItems = relationships?.items?.data
        let includedItemCount = includedItems?.count
        let itemTotal = relationships?.items?.meta?.paging.total
        let itemLimit = relationships?.items?.meta?.paging.limit
        let itemNextCursor = relationships?.items?.meta?.paging.nextCursor
        let itemsTruncated: Bool? = if itemNextCursor != nil {
            true
        } else {
            itemTotal.flatMap { total in
                includedItemCount.map { total > $0 }
            }
        }
        var result: [String: Any] = [
            "id": submission.id,
            "type": submission.type,
            "platform": (submission.attributes?.platform?.rawValue).jsonSafe,
            "submitted_date": (submission.attributes?.submittedDate).jsonSafe,
            "state": (submission.attributes?.state?.rawValue).jsonSafe,
            "app_id": (relationships?.app?.data?.id).jsonSafe,
            "item_ids": (includedItems?.map(\.id)).jsonSafe,
            "item_included_count": includedItemCount.jsonSafe,
            "item_total": itemTotal.jsonSafe,
            "item_limit": itemLimit.jsonSafe,
            "item_next_cursor": itemNextCursor.jsonSafe,
            "items_truncated": itemsTruncated.jsonSafe,
            "items_complete": itemsTruncated.map { !$0 }.jsonSafe,
            "items_completeness_known": (itemsTruncated != nil),
            "app_store_version_for_review_id": (relationships?.appStoreVersionForReview?.data?.id).jsonSafe,
            "submitted_by_actor_id": (relationships?.submittedByActor?.data?.id).jsonSafe,
            "last_updated_by_actor_id": (relationships?.lastUpdatedByActor?.data?.id).jsonSafe,
            "self_url": (submission.links?.`self`).jsonSafe,
            "recovery": submissionRecovery(submissionID: submission.id)
        ]
        if itemsTruncated == true {
            result["items_inspection"] = [
                "tool": "review_submissions_list_items",
                "arguments": [
                    "submission_id": submission.id,
                    "limit": 200
                ] as [String: Any],
                "continue_with_next_url": true
            ] as [String: Any]
        }
        return result
    }

    private func formatItem(_ item: ASCReviewSubmissionItem) -> [String: Any] {
        let relations = itemRelations(item.relationships)
        return [
            "id": item.id,
            "type": item.type,
            "state": (item.attributes?.state?.rawValue).jsonSafe,
            "resource_type": (relations.first?.name).jsonSafe,
            "resource_id": (relations.first?.identifier.id).jsonSafe,
            "resource_jsonapi_type": (relations.first?.identifier.type).jsonSafe,
            "relations": relations.map { relation in
                [
                    "name": relation.name,
                    "id": relation.identifier.id,
                    "type": relation.identifier.type,
                    "scoped": relation.scoped
                ] as [String: Any]
            },
            "self_url": (item.links?.`self`).jsonSafe
        ]
    }

    private func validateCreatedItem(
        _ item: ASCReviewSubmissionItem,
        requested: (relation: ASCReviewSubmissionItemRelation, resourceID: String)
    ) throws {
        try validateItem(item, expectedID: nil, context: "review submission item create")

        let relations = itemRelations(item.relationships)
        guard relations.count == 1, let relation = relations.first else {
            throw ASCError.parsing(
                "Apple did not confirm exactly one review item relationship"
            )
        }
        guard !relation.scoped,
              relation.name == requested.relation.rawValue,
              relation.identifier.type == requested.relation.resourceType,
              relation.identifier.id == requested.resourceID else {
            throw ASCError.parsing(
                "Apple returned a review item relationship that does not match the requested resource"
            )
        }
    }

    private func itemRelations(
        _ relationships: ASCReviewSubmissionItem.Relationships?
    ) -> [(name: String, identifier: ASCResourceIdentifier, scoped: Bool)] {
        guard let relationships else { return [] }
        let candidates: [(String, ASCRelationship?, Bool)] = [
            ("appStoreVersion", relationships.appStoreVersion, false),
            ("appCustomProductPageVersion", relationships.appCustomProductPageVersion, false),
            ("appStoreVersionExperiment", relationships.appStoreVersionExperiment, false),
            ("appStoreVersionExperimentV2", relationships.appStoreVersionExperimentV2, false),
            ("appEvent", relationships.appEvent, false),
            ("backgroundAssetVersion", relationships.backgroundAssetVersion, false),
            ("gameCenterAchievementVersion", relationships.gameCenterAchievementVersion, true),
            ("gameCenterActivityVersion", relationships.gameCenterActivityVersion, true),
            ("gameCenterChallengeVersion", relationships.gameCenterChallengeVersion, true),
            ("gameCenterLeaderboardSetVersion", relationships.gameCenterLeaderboardSetVersion, true),
            ("gameCenterLeaderboardVersion", relationships.gameCenterLeaderboardVersion, true),
            ("inAppPurchaseVersion", relationships.inAppPurchaseVersion, false),
            ("subscriptionVersion", relationships.subscriptionVersion, false),
            ("subscriptionGroupVersion", relationships.subscriptionGroupVersion, false)
        ]
        return candidates.compactMap { name, relationship, scoped in
            relationship?.data.map { (name, $0, scoped) }
        }
    }

    private func formatIncluded(_ resource: ASCReviewSubmissionIncludedResource) -> [String: Any] {
        var result: [String: Any] = [
            "id": resource.id,
            "type": resource.type
        ]
        if let attributes = resource.attributes {
            result["attributes"] = attributes.asAny
        }
        if let relationships = resource.relationships {
            result["relationships"] = relationships.asAny
        }
        if let links = resource.links {
            result["links"] = links.asAny
        }
        return result
    }

    private func appendIncluded(
        _ included: [ASCReviewSubmissionIncludedResource]?,
        to result: inout [String: Any]
    ) {
        guard let included else { return }
        result["included"] = included.map(formatIncluded)
        result["actors"] = included.filter { $0.type == "actors" }.map(formatIncluded)
        result["included_apps"] = included.filter { $0.type == "apps" }.map(formatIncluded)
        result["included_app_store_versions"] = included
            .filter { $0.type == "appStoreVersions" }
            .map(formatIncluded)
        result["included_items"] = included
            .filter { $0.type == "reviewSubmissionItems" }
            .map(formatIncluded)
    }

    private func appendPaging(
        links: ASCPagedDocumentLinks,
        meta: ASCReviewSubmissionPagingInformation?,
        to result: inout [String: Any]
    ) {
        if let nextURL = links.next {
            result["next_url"] = nextURL
        }
        if let total = meta?.paging.total {
            result["total"] = total
        }
    }

    private func submissionRecovery(submissionID: String) -> [String: Any] {
        [
            "submission_id": submissionID,
            "inspect_tool": "review_submissions_get",
            "list_items_tool": "review_submissions_list_items",
            "add_item_tool": "review_submissions_add_item",
            "update_item_tool": "review_submissions_update_item",
            "remove_item_tool": "review_submissions_remove_item",
            "submit_tool": "review_submissions_submit",
            "cancel_tool": "review_submissions_cancel"
        ]
    }

    private func itemRecovery(
        submissionID: String?,
        itemID: String
    ) -> [String: Any] {
        var result: [String: Any] = [
            "item_id": itemID,
            "update_tool": "review_submissions_update_item",
            "remove_tool": "review_submissions_remove_item"
        ]
        if let submissionID {
            result["submission_id"] = submissionID
            result["inspect_tool"] = "review_submissions_list_items"
        }
        return result
    }

    private func recoveryStep(
        tool: String,
        arguments: [String: Value],
        continueWithNextURL: Bool = false
    ) -> Value {
        var step: [String: Value] = [
            "tool": .string(tool),
            "arguments": .object(arguments)
        ]
        if continueWithNextURL {
            step["continue_with_next_url"] = .bool(true)
        }
        return .object(step)
    }

    private func submissionListInspection(
        appID: String,
        requestedPlatform: Value?
    ) -> Value {
        var arguments: [String: Value] = [
            "app_id": .string(appID),
            "include": .array(Self.submissionIncludes.map(Value.string)),
            "item_limit": .int(50),
            "limit": .int(200)
        ]
        if let platform = requestedPlatform?.stringValue {
            arguments["platforms"] = .string(platform)
        }
        var match: [String: Value] = [
            "app_id": .string(appID)
        ]
        if let requestedPlatform {
            match["platform"] = requestedPlatform
        }
        return .object([
            "tool": .string("review_submissions_list"),
            "arguments": .object(arguments),
            "continue_with_next_url": .bool(true),
            "match": .object(match)
        ])
    }

    private func submissionInspection(submissionID: String) -> Value {
        .object([
            "get_submission": recoveryStep(
                tool: "review_submissions_get",
                arguments: ["submission_id": .string(submissionID)]
            ),
            "list_items": itemListInspection(
                submissionID: submissionID,
                itemID: nil,
                requestedRelation: nil
            )
        ])
    }

    private func itemListInspection(
        submissionID: String,
        itemID: String?,
        requestedRelation: (relation: ASCReviewSubmissionItemRelation, resourceID: String)?
    ) -> Value {
        var match: [String: Value] = [
            "submission_id": .string(submissionID)
        ]
        if let itemID {
            match["item_id"] = .string(itemID)
        }
        if let requestedRelation {
            match["resource_type"] = .string(requestedRelation.relation.rawValue)
            match["resource_jsonapi_type"] = .string(requestedRelation.relation.resourceType)
            match["resource_id"] = .string(requestedRelation.resourceID)
        }
        return .object([
            "tool": .string("review_submissions_list_items"),
            "arguments": .object([
                "submission_id": .string(submissionID),
                "limit": .int(200)
            ]),
            "continue_with_next_url": .bool(true),
            "match": .object(match)
        ])
    }

    private func committedUnverifiedMutationFailure(
        operation: String,
        reason: Error,
        identifiers: [String: Value],
        inspection: Value
    ) -> CallTool.Result {
        let message = "Apple accepted the \(operation) mutation, but the returned resource identity or document contract could not be verified. Inspect the existing resource before retrying."
        var payload = identifiers
        payload["success"] = .bool(false)
        payload["error"] = .string(message)
        payload["operation"] = .string(operation)
        payload["write_outcome"] = .string("committed_unverified")
        payload["operationCommitState"] = .string("committed_unverified")
        payload["operationCommitted"] = .bool(true)
        payload["outcomeUnknown"] = .bool(false)
        payload["inspectionRequired"] = .bool(true)
        payload["mutationAttempted"] = .bool(true)
        payload["retrySafe"] = .bool(false)
        payload["inspection"] = inspection
        payload["cause"] = structuredError(reason)
        return MCPResult.json(
            .object(payload),
            text: "Error: \(message)",
            isError: true
        )
    }

    private func encodeMutationBody<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw ASCError.parsing("Failed to encode review submission mutation body: \(error.localizedDescription)")
        }
    }

    private func decodeMutationResponse<T: Decodable>(
        _ data: Data,
        as type: T.Type
    ) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ASCError.parsing("Failed to decode \(type): \(error.localizedDescription)")
        }
    }

    private func preRequestEncodingFailure(
        operation: String,
        error: Error,
        identifiers: [String: Value]
    ) -> CallTool.Result {
        var details = identifiers
        details["operation"] = .string(operation)
        details["write_outcome"] = .string("not_attempted")
        details["operationCommitState"] = .string("not_attempted")
        details["mutationAttempted"] = .bool(false)
        details["retrySafe"] = .bool(true)
        details["cause"] = structuredError(error)
        return MCPResult.error(
            "Failed to prepare review submission \(operation): \(error.localizedDescription)",
            details: .object(details)
        )
    }

    private func mutationRequestFailure(
        operation: String,
        error: Error,
        identifiers: [String: Value],
        inspection: Value,
        retry: Value? = nil
    ) -> CallTool.Result {
        let disposition = ASCNonIdempotentWriteRecovery.failureDisposition(
            for: error,
            phase: .request
        )
        var details = identifiers
        details["operation"] = .string(operation)
        details["write_outcome"] = .string(disposition.rawValue)
        details["operationCommitState"] = .string(disposition.rawValue)
        details["mutationAttempted"] = .bool(true)
        details["retrySafe"] = .bool(false)
        details["cause"] = structuredError(error)
        details["inspection"] = inspection
        if let retry {
            details["retry"] = retry
        }
        switch disposition {
        case .rejected:
            break
        case .outcomeUnknown:
            details["outcomeUnknown"] = .bool(true)
            details["inspectionRequired"] = .bool(true)
        case .committedUnverified:
            details["operationCommitted"] = .bool(true)
            details["inspectionRequired"] = .bool(true)
        }
        return MCPResult.error(
            "Failed to perform review submission \(operation): \(error.localizedDescription)",
            details: .object(details)
        )
    }

    private func deletionFailure(
        error: Error,
        submissionID: String,
        itemID: String
    ) -> CallTool.Result {
        let state: String
        let operationCommitState: String
        let retrySafe: Bool
        let message: String
        var extra: [String: Value] = [:]

        if let ascError = error as? ASCError {
            switch ascError {
            case .deleteOutcomeUnknown:
                state = "unknown"
                operationCommitState = "unknown"
                retrySafe = false
                extra["outcomeUnknown"] = .bool(true)
                message = "The review submission item delete outcome is unknown. Inspect every page of the exact parent submission before another delete attempt."
            case .deleteCommittedUnverified:
                state = "committed_unverified"
                operationCommitState = "committed_unverified"
                retrySafe = false
                extra["operationCommitted"] = .bool(true)
                extra["outcomeUnknown"] = .bool(false)
                extra["inspectionRequired"] = .bool(true)
                message = "Apple accepted the review submission item delete with an unexpected success status, but completion is unverified. Inspect every page of the exact parent submission before another delete attempt."
            default:
                state = "rejected"
                operationCommitState = "rejected"
                retrySafe = true
                message = "Failed to remove review submission item: \(error.localizedDescription)"
            }
        } else {
            state = "rejected"
            operationCommitState = "rejected"
            retrySafe = true
            message = "Failed to remove review submission item: \(error.localizedDescription)"
        }

        var details: [String: Value] = [
            "operation": .string("remove_item"),
            "submission_id": .string(submissionID),
            "item_id": .string(itemID),
            "deletionState": .string(state),
            "operationCommitState": .string(operationCommitState),
            "mutationAttempted": .bool(true),
            "retrySafe": .bool(retrySafe),
            "cause": structuredError(error),
            "inspection": itemListInspection(
                submissionID: submissionID,
                itemID: itemID,
                requestedRelation: nil
            )
        ]
        details.merge(extra) { _, new in new }
        return MCPResult.error(message, details: .object(details))
    }

    private func membershipPreflightFailure(
        error: Error,
        operation: String,
        submissionID: String,
        itemID: String
    ) -> CallTool.Result {
        MCPResult.error(
            "Failed to verify review submission item membership before \(operation): \(error.localizedDescription)",
            details: .object([
                "operation": .string(operation),
                "submission_id": .string(submissionID),
                "item_id": .string(itemID),
                "mutationAttempted": .bool(false),
                "retrySafe": .bool(true),
                "cause": structuredError(error),
                "inspection": itemListInspection(
                    submissionID: submissionID,
                    itemID: itemID,
                    requestedRelation: nil
                )
            ])
        )
    }

    private func structuredError(_ error: Error) -> Value {
        if let error = error as? ASCError {
            return error.structuredValue
        }
        return .object([
            "type": .string("unexpected"),
            "message": .string(Redactor.redact(error.localizedDescription))
        ])
    }

}

private struct ReviewSubmissionArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
