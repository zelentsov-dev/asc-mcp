import Foundation
import MCP

// MARK: - Tool Handlers
extension PromotedPurchasesWorker {

    /// Lists promoted purchases for an app
    /// - Returns: JSON array of promoted purchases with visibility, enabled state, and status
    /// - Throws: On network or decoding errors
    func listPromotedPurchases(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments: [String: Value]
        let appId: String
        let limit: Int
        do {
            arguments = try promotedArguments(
                params.arguments,
                allowed: ["app_id", "limit", "next_url"]
            )
            appId = try promotedIdentifier("app_id", from: arguments)
            limit = try promotedLimit(arguments["limit"])
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate promoted purchase list")
        }

        do {
            let response: ASCPromotedPurchasesResponse
            let endpoint = "/v1/apps/\(try ASCPathSegment.encode(appId))/promotedPurchases"
            let queryParams = ["limit": String(limit)]
            let nextURL = try promotedPaginationURL(arguments["next_url"])
            let paginationScope = promotedPurchasePaginationScope(
                path: endpoint,
                query: queryParams
            )
            let currentPageRequest: PaginationRequest?

            if let nextURL {
                currentPageRequest = try httpClient.validatedScopedLink(
                    nextURL,
                    scope: paginationScope
                )
                response = try await httpClient.getPage(
                    nextURL,
                    scope: paginationScope,
                    as: ASCPromotedPurchasesResponse.self
                )
            } else {
                currentPageRequest = nil
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCPromotedPurchasesResponse.self
                )
            }

            let selfQuery = currentPageRequest?.parameters ?? queryParams
            let selfRequest = try validatePromotedDocumentSelf(
                response.links.`self`,
                expectedPath: endpoint,
                requiredQuery: selfQuery,
                allowedQueryNames: Set(selfQuery.keys),
                requiresCursor: currentPageRequest != nil,
                context: "promoted purchase list"
            )
            let nextRequest = try validatePromotedNextPageLink(
                response.links.next,
                scope: paginationScope,
                currentCursor: selfRequest.parameters["cursor"],
                context: "promoted purchase list"
            )
            _ = try validatePromotedPaging(
                response.meta,
                expectedLimit: limit,
                pageCount: response.data.count,
                nextRequest: nextRequest,
                context: "promoted purchase list"
            )
            try validatePromotedPurchaseCollection(
                response.data,
                context: "promoted purchase list"
            )
            try validateIncludedPromotedPurchaseResources(
                response.included,
                purchases: response.data,
                context: "promoted purchase list"
            )
            let purchases = response.data.map { formatPromotedPurchase($0) }

            var result: [String: Any] = [
                "success": true,
                "promoted_purchases": purchases,
                "count": purchases.count
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list promoted purchases: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a specific promoted purchase
    /// - Returns: JSON with promoted purchase details (visibility, enabled, state)
    /// - Throws: On network or decoding errors
    func getPromotedPurchase(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let promotedPurchaseId: String
        do {
            let arguments = try promotedArguments(
                params.arguments,
                allowed: ["promoted_purchase_id"]
            )
            promotedPurchaseId = try promotedIdentifier("promoted_purchase_id", from: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate promoted purchase lookup")
        }

        do {
            let endpoint = "/v1/promotedPurchases/\(try ASCPathSegment.encode(promotedPurchaseId))"
            let query = ["include": "inAppPurchaseV2,subscription"]
            let response: ASCPromotedPurchaseResponse = try await httpClient.get(
                endpoint,
                parameters: query,
                as: ASCPromotedPurchaseResponse.self
            )
            try validatePromotedDocumentSelf(
                response.links.`self`,
                expectedPath: endpoint,
                requiredQuery: query,
                allowedQueryNames: Set(query.keys),
                context: "promoted purchase lookup"
            )
            try validatePromotedPurchase(
                response.data,
                expectedID: promotedPurchaseId,
                context: "promoted purchase lookup"
            )
            try validateIncludedPromotedPurchaseResources(
                response.included,
                purchases: [response.data],
                context: "promoted purchase lookup"
            )

            let purchase = formatPromotedPurchase(response.data, included: response.included)

            let result = [
                "success": true,
                "promoted_purchase": purchase
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get promoted purchase: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a promoted purchase for an IAP or subscription
    /// - Returns: JSON with created promoted purchase details
    /// - Throws: On network or encoding errors
    func createPromotedPurchase(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments: [String: Value]
        let appId: String
        let visible: Bool
        let enabled: PromotedPurchaseNullableBool?
        let iapId: String?
        let subscriptionId: String?
        do {
            arguments = try promotedArguments(
                params.arguments,
                allowed: ["app_id", "visible", "enabled", "iap_id", "subscription_id"]
            )
            appId = try promotedIdentifier("app_id", from: arguments)
            guard let parsedVisible = arguments["visible"]?.boolValue else {
                throw PromotedPurchaseInputError("visible must be a boolean")
            }
            visible = parsedVisible
            enabled = try nullableBool("enabled", from: arguments)
            iapId = try promotedOptionalIdentifier("iap_id", from: arguments)
            subscriptionId = try promotedOptionalIdentifier("subscription_id", from: arguments)
            guard (iapId != nil) != (subscriptionId != nil) else {
                throw PromotedPurchaseInputError("Provide exactly one of 'iap_id' or 'subscription_id'")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate promoted purchase creation")
        }

        let request: CreatePromotedPurchaseRequest
        do {
            let iapRelationship: CreatePromotedPurchaseRequest.IAPRelationship?
            if let iapId = iapId {
                iapRelationship = CreatePromotedPurchaseRequest.IAPRelationship(
                    data: ASCResourceIdentifier(type: "inAppPurchases", id: iapId)
                )
            } else {
                iapRelationship = nil
            }

            let subscriptionRelationship: CreatePromotedPurchaseRequest.SubscriptionRelationship?
            if let subscriptionId = subscriptionId {
                subscriptionRelationship = CreatePromotedPurchaseRequest.SubscriptionRelationship(
                    data: ASCResourceIdentifier(type: "subscriptions", id: subscriptionId)
                )
            } else {
                subscriptionRelationship = nil
            }

            request = CreatePromotedPurchaseRequest(
                data: CreatePromotedPurchaseRequest.CreateData(
                    attributes: CreatePromotedPurchaseRequest.Attributes(
                        visibleForAllUsers: visible,
                        enabled: enabled
                    ),
                    relationships: CreatePromotedPurchaseRequest.Relationships(
                        app: CreatePromotedPurchaseRequest.AppRelationship(
                            data: ASCResourceIdentifier(type: "apps", id: appId)
                        ),
                        inAppPurchaseV2: iapRelationship,
                        subscription: subscriptionRelationship
                    )
                )
            )
        }

        let body: Data
        do {
            body = try JSONEncoder().encode(request)
        } catch {
            return MCPResult.error(error, prefix: "Failed to encode promoted purchase creation")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/promotedPurchases", body: body)
        } catch {
            return promotedCreateFailure(
                error: error,
                phase: .request,
                appID: appId,
                visible: visible,
                enabled: arguments["enabled"],
                iapID: iapId,
                subscriptionID: subscriptionId
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Promoted purchase create"
            )
            let response = try JSONDecoder().decode(ASCPromotedPurchaseResponse.self, from: receipt.data)
            try validatePromotedPurchase(
                response.data,
                expectedIAPID: iapId,
                expectedSubscriptionID: subscriptionId,
                context: "promoted purchase create response"
            )
            try validatePromotedDocumentSelf(
                response.links.`self`,
                expectedPath: "/v1/promotedPurchases/\(try ASCPathSegment.encode(response.data.id))",
                context: "promoted purchase create response"
            )
            try validateIncludedPromotedPurchaseResources(
                response.included,
                purchases: [response.data],
                context: "promoted purchase create response"
            )
            let purchase = formatPromotedPurchase(response.data)

            let result: [String: Any] = [
                "success": true,
                "operation": "create",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "promoted_purchase": purchase
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return promotedCreateFailure(
                error: promotedAcceptedMutationError(
                    error,
                    method: "POST",
                    expectedStatusCode: 201,
                    actualStatusCode: receipt.statusCode
                ),
                phase: .acceptedResponse,
                appID: appId,
                visible: visible,
                enabled: arguments["enabled"],
                iapID: iapId,
                subscriptionID: subscriptionId
            )
        }
    }

    /// Updates a promoted purchase
    /// - Returns: JSON with updated promoted purchase details
    /// - Throws: On network or encoding errors
    func updatePromotedPurchase(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments: [String: Value]
        let promotedPurchaseId: String
        let visible: PromotedPurchaseNullableBool?
        let enabled: PromotedPurchaseNullableBool?
        do {
            arguments = try promotedArguments(
                params.arguments,
                allowed: ["promoted_purchase_id", "visible", "enabled"]
            )
            promotedPurchaseId = try promotedIdentifier("promoted_purchase_id", from: arguments)
            visible = try nullableBool("visible", from: arguments)
            enabled = try nullableBool("enabled", from: arguments)
            guard visible != nil || enabled != nil else {
                throw PromotedPurchaseInputError("At least one update field is required: visible or enabled")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate promoted purchase update")
        }

        let request = UpdatePromotedPurchaseRequest(
            data: UpdatePromotedPurchaseRequest.UpdateData(
                id: promotedPurchaseId,
                attributes: UpdatePromotedPurchaseRequest.Attributes(
                    visibleForAllUsers: visible,
                    enabled: enabled
                )
            )
        )
        let body: Data
        do {
            body = try JSONEncoder().encode(request)
        } catch {
            return MCPResult.error(error, prefix: "Failed to encode promoted purchase update")
        }

        let endpoint: String
        do {
            endpoint = "/v1/promotedPurchases/\(try ASCPathSegment.encode(promotedPurchaseId, field: "promoted_purchase_id"))"
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate promoted purchase update")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(endpoint, body: body)
        } catch {
            return promotedTargetMutationFailure(
                operation: "promoted_update",
                targetID: promotedPurchaseId,
                requestedArguments: promotedRequestedUpdateArguments(arguments),
                error: error,
                phase: .request
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 200,
                context: "Promoted purchase update"
            )
            let response = try JSONDecoder().decode(ASCPromotedPurchaseResponse.self, from: receipt.data)
            try validatePromotedPurchase(
                response.data,
                expectedID: promotedPurchaseId,
                context: "promoted purchase update response"
            )
            try validatePromotedDocumentSelf(
                response.links.`self`,
                expectedPath: endpoint,
                context: "promoted purchase update response"
            )
            try validateIncludedPromotedPurchaseResources(
                response.included,
                purchases: [response.data],
                context: "promoted purchase update response"
            )

            let purchase = formatPromotedPurchase(response.data)

            let result: [String: Any] = [
                "success": true,
                "operation": "update",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "promoted_purchase": purchase
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return promotedTargetMutationFailure(
                operation: "promoted_update",
                targetID: promotedPurchaseId,
                requestedArguments: promotedRequestedUpdateArguments(arguments),
                error: promotedAcceptedMutationError(
                    error,
                    method: "PATCH",
                    expectedStatusCode: 200,
                    actualStatusCode: receipt.statusCode
                ),
                phase: .acceptedResponse
            )
        }
    }

    /// Deletes a promoted purchase
    /// - Returns: JSON confirmation
    /// - Throws: On network errors
    func deletePromotedPurchase(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let promotedPurchaseId: String
        do {
            let arguments = try promotedArguments(
                params.arguments,
                allowed: ["promoted_purchase_id", "confirm_promoted_purchase_id"]
            )
            promotedPurchaseId = try promotedIdentifier("promoted_purchase_id", from: arguments)
            let confirmationID = try promotedIdentifier(
                "confirm_promoted_purchase_id",
                from: arguments
            )
            guard confirmationID == promotedPurchaseId else {
                throw PromotedPurchaseInputError(
                    "Deleting a promoted purchase is irreversible. Set confirm_promoted_purchase_id to the exact promoted_purchase_id to continue."
                )
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate promoted purchase deletion")
        }

        let receipt: ASCDeleteReceipt
        do {
            receipt = try await httpClient.deleteReceipt(
                "/v1/promotedPurchases/\(try ASCPathSegment.encode(promotedPurchaseId, field: "promoted_purchase_id"))"
            )
        } catch {
            return promotedDeleteFailure(targetID: promotedPurchaseId, error: error)
        }

        guard receipt.statusCode == 204 else {
            return promotedDeleteFailure(
                targetID: promotedPurchaseId,
                error: ASCError.deleteCommittedUnverified(statusCode: receipt.statusCode)
            )
        }

        return MCPResult.jsonObject([
            "success": true,
            "operation": "delete",
            "operationCommitted": true,
            "operationCommitState": "committed",
            "deleted": true,
            "deletionState": "confirmed",
            "outcomeUnknown": false,
            "retrySafe": false,
            "statusCode": receipt.statusCode,
            "promotedPurchaseId": promotedPurchaseId,
            "message": "Promoted purchase '\(promotedPurchaseId)' deleted"
        ])
    }

    func reorderPromotedPurchases(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let appID: String
        let requestedOrder: [String]
        do {
            let arguments = try promotedArguments(
                params.arguments,
                allowed: ["app_id", "promoted_purchase_ids"]
            )
            appID = try promotedIdentifier("app_id", from: arguments)
            requestedOrder = try promotedIdentifierArray(
                "promoted_purchase_ids",
                from: arguments
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate promoted purchase reorder")
        }

        let preflightOrder: [String]
        do {
            preflightOrder = try await promotedPurchaseOrder(
                appID: appID,
                context: "promoted purchase reorder preflight"
            )
            guard preflightOrder.count == requestedOrder.count,
                  Set(preflightOrder) == Set(requestedOrder) else {
                throw PromotedPurchaseInputError(
                    "promoted_purchase_ids must contain every current promoted purchase ID exactly once"
                )
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed promoted purchase reorder preflight")
        }

        if preflightOrder == requestedOrder {
            return MCPResult.jsonObject([
                "success": true,
                "operation": "reorder",
                "operationCommitted": false,
                "operationCommitState": "not_attempted",
                "mutationAttempted": false,
                "changed": false,
                "retrySafe": true,
                "appId": appID,
                "order": preflightOrder
            ])
        }

        let body: Data
        do {
            body = try JSONEncoder().encode(
                ReorderPromotedPurchasesRequest(
                    data: requestedOrder.map {
                        ASCResourceIdentifier(type: "promotedPurchases", id: $0)
                    }
                )
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to encode promoted purchase reorder")
        }

        let endpoint: String
        do {
            endpoint = "/v1/apps/\(try ASCPathSegment.encode(appID, field: "app_id"))/relationships/promotedPurchases"
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate promoted purchase reorder")
        }
        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(endpoint, body: body)
        } catch {
            return promotedReorderFailure(
                appID: appID,
                requestedOrder: requestedOrder,
                preflightOrder: preflightOrder,
                error: error,
                phase: .request
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 204,
                context: "Promoted purchase reorder"
            )
            let confirmedOrder = try await promotedPurchaseOrder(
                appID: appID,
                context: "promoted purchase reorder postflight"
            )
            guard confirmedOrder == requestedOrder else {
                throw PromotedPurchaseInputError(
                    "Promoted purchase reorder postflight did not preserve the requested order"
                )
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "reorder",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "mutationAttempted": true,
                "changed": preflightOrder != confirmedOrder,
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "appId": appID,
                "order": confirmedOrder
            ])
        } catch {
            return promotedReorderFailure(
                appID: appID,
                requestedOrder: requestedOrder,
                preflightOrder: preflightOrder,
                error: promotedAcceptedMutationError(
                    error,
                    method: "PATCH",
                    expectedStatusCode: 204,
                    actualStatusCode: receipt.statusCode
                ),
                phase: .acceptedResponse
            )
        }
    }

    // MARK: - Image Handlers

    /// Returns migration guidance for the promoted purchase image upload endpoint absent from the pinned specification.
    /// - Returns: A structured deprecation error with supported replacement tools.
    /// - Throws: This handler does not throw.
    func uploadPromotedPurchaseImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try promotedArguments(
                params.arguments,
                allowed: ["promoted_purchase_id", "file_path"]
            )
            _ = try promotedIdentifier("promoted_purchase_id", from: arguments)
            guard let filePath = arguments["file_path"]?.stringValue,
                  !filePath.isEmpty,
                  filePath == filePath.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw PromotedPurchaseInputError("file_path must be a non-empty string")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate promoted purchase image migration")
        }
        return promotedImageDeprecation(tool: "promoted_upload_image")
    }

    /// Returns migration guidance for the promoted purchase image resource absent from the pinned specification.
    /// - Returns: A structured deprecation error with supported replacement tools.
    /// - Throws: This handler does not throw.
    func getPromotedPurchaseImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try promotedArguments(params.arguments, allowed: ["image_id"])
            _ = try promotedIdentifier("image_id", from: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate promoted purchase image migration")
        }
        return promotedImageDeprecation(tool: "promoted_get_image")
    }

    /// Returns migration guidance for the promoted purchase image delete endpoint absent from the pinned specification.
    /// - Returns: A structured deprecation error with supported replacement tools.
    /// - Throws: This handler does not throw.
    func deletePromotedPurchaseImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try promotedArguments(params.arguments, allowed: ["image_id"])
            _ = try promotedIdentifier("image_id", from: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate promoted purchase image migration")
        }
        return promotedImageDeprecation(tool: "promoted_delete_image")
    }

    /// Returns migration guidance for the promoted purchase image relationship absent from the pinned specification.
    /// - Returns: A structured deprecation error with supported replacement tools.
    /// - Throws: This handler does not throw.
    func getPromotedPurchaseImageForPurchase(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let arguments = try promotedArguments(
                params.arguments,
                allowed: ["promoted_purchase_id"]
            )
            _ = try promotedIdentifier("promoted_purchase_id", from: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate promoted purchase image migration")
        }
        return promotedImageDeprecation(tool: "promoted_get_image_for_purchase")
    }

    // MARK: - Formatting

    private func promotedImageDeprecation(tool: String) -> CallTool.Result {
        MCPResult.error(
            "Promoted purchase image endpoints are absent from pinned executable OpenAPI 4.4.1; Apple's executable contract no longer provides them.",
            details: .object([
                "deprecated": .bool(true),
                "tool": .string(tool),
                "migration": .string("Use promoted_get to resolve the linked product, select its current version, then use the matching active version-scoped IAP or subscription image tools."),
                "replacement_tools": .array([
                    .string("iap_get_version_image"),
                    .string("iap_list_version_images"),
                    .string("iap_upload_version_image"),
                    .string("iap_get_version_image_resource"),
                    .string("iap_delete_version_image"),
                    .string("subscriptions_list_version_images"),
                    .string("subscriptions_upload_version_image"),
                    .string("subscriptions_get_version_image"),
                    .string("subscriptions_delete_version_image")
                ])
            ])
        )
    }

    private func promotedArguments(
        _ arguments: [String: Value]?,
        allowed: Set<String>
    ) throws -> [String: Value] {
        let arguments = arguments ?? [:]
        let unsupported = Set(arguments.keys).subtracting(allowed).sorted()
        guard unsupported.isEmpty else {
            throw PromotedPurchaseInputError(
                "Unsupported parameter(s): \(unsupported.joined(separator: ", "))"
            )
        }
        return arguments
    }

    private func promotedIdentifier(
        _ name: String,
        from arguments: [String: Value]
    ) throws -> String {
        guard let value = arguments[name] else {
            throw PromotedPurchaseInputError("Required parameter '\(name)' is missing")
        }
        guard let identifier = value.stringValue else {
            throw PromotedPurchaseInputError("\(name) must be a string")
        }
        let encoded = try ASCPathSegment.encode(identifier, field: name)
        guard encoded == identifier else {
            throw PromotedPurchaseInputError(
                "\(name) must be a canonical App Store Connect resource ID"
            )
        }
        return identifier
    }

    private func promotedOptionalIdentifier(
        _ name: String,
        from arguments: [String: Value]
    ) throws -> String? {
        guard arguments[name] != nil else { return nil }
        return try promotedIdentifier(name, from: arguments)
    }

    private func promotedIdentifierArray(
        _ name: String,
        from arguments: [String: Value]
    ) throws -> [String] {
        guard let values = arguments[name]?.arrayValue else {
            throw PromotedPurchaseInputError("\(name) must be a JSON array of resource IDs")
        }
        guard !values.isEmpty else {
            throw PromotedPurchaseInputError("\(name) must contain at least one resource ID")
        }
        var identities = Set<String>()
        return try values.enumerated().map { index, value in
            guard let identifier = value.stringValue else {
                throw PromotedPurchaseInputError("\(name)[\(index)] must be a string")
            }
            let encoded = try ASCPathSegment.encode(identifier, field: "\(name)[\(index)]")
            guard encoded == identifier else {
                throw PromotedPurchaseInputError(
                    "\(name)[\(index)] must be a canonical App Store Connect resource ID"
                )
            }
            guard identities.insert(identifier).inserted else {
                throw PromotedPurchaseInputError("\(name) must not contain duplicate IDs")
            }
            return identifier
        }
    }

    private func promotedLimit(_ value: Value?) throws -> Int {
        guard let value else { return 25 }
        guard let limit = value.intValue, (1...200).contains(limit) else {
            throw PromotedPurchaseInputError("limit must be an integer between 1 and 200")
        }
        return limit
    }

    private func promotedPaginationURL(_ value: Value?) throws -> String? {
        guard let nextURL = try paginationURL(from: value) else { return nil }
        guard nextURL.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw PromotedPurchaseInputError("next_url must not contain whitespace")
        }
        return nextURL
    }

    private func validatePromotedPurchaseCollection(
        _ purchases: [ASCPromotedPurchase],
        context: String
    ) throws {
        var identities = Set<String>()
        for purchase in purchases {
            try validatePromotedPurchase(purchase, context: context)
            guard identities.insert(purchase.id).inserted else {
                throw PromotedPurchaseInputError(
                    "Apple returned duplicate promoted purchase identity in \(context)"
                )
            }
        }
    }

    private func validatePromotedPurchase(
        _ purchase: ASCPromotedPurchase,
        expectedID: String? = nil,
        expectedIAPID: String? = nil,
        expectedSubscriptionID: String? = nil,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: purchase.type,
            id: purchase.id,
            expectedType: "promotedPurchases",
            expectedID: expectedID,
            context: context
        )

        let iap = purchase.relationships?.inAppPurchaseV2?.data
        let subscription = purchase.relationships?.subscription?.data
        guard iap == nil || subscription == nil else {
            throw PromotedPurchaseInputError(
                "Apple returned multiple product relationships in \(context)"
            )
        }
        if expectedIAPID != nil, iap == nil {
            throw PromotedPurchaseInputError(
                "Apple omitted the requested IAP relationship in \(context)"
            )
        }
        if expectedSubscriptionID != nil, subscription == nil {
            throw PromotedPurchaseInputError(
                "Apple omitted the requested subscription relationship in \(context)"
            )
        }
        if let iap {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: iap.type,
                id: iap.id,
                expectedType: "inAppPurchases",
                expectedID: expectedIAPID,
                context: "\(context) IAP relationship"
            )
            guard expectedSubscriptionID == nil else {
                throw PromotedPurchaseInputError(
                    "Apple returned an IAP relationship for a subscription promotion in \(context)"
                )
            }
        }
        if let subscription {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: subscription.type,
                id: subscription.id,
                expectedType: "subscriptions",
                expectedID: expectedSubscriptionID,
                context: "\(context) subscription relationship"
            )
            guard expectedIAPID == nil else {
                throw PromotedPurchaseInputError(
                    "Apple returned a subscription relationship for an IAP promotion in \(context)"
                )
            }
        }
    }

    private func validateIncludedPromotedPurchaseResources(
        _ included: [PromotedPurchaseIncludedResource]?,
        purchases: [ASCPromotedPurchase],
        context: String
    ) throws {
        guard let included, !included.isEmpty else { return }
        let expectedIdentities = Set(purchases.flatMap { purchase in
            [
                purchase.relationships?.inAppPurchaseV2?.data,
                purchase.relationships?.subscription?.data
            ].compactMap { $0 }.map { "\($0.type):\($0.id)" }
        })
        guard !expectedIdentities.isEmpty else {
            throw PromotedPurchaseInputError(
                "Apple returned included products without a primary product linkage in \(context)"
            )
        }
        var identities = Set<String>()
        for resource in included {
            guard ["inAppPurchases", "subscriptions"].contains(resource.type) else {
                throw PromotedPurchaseInputError(
                    "Apple returned an unsupported included resource in \(context)"
                )
            }
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: resource.type,
                id: resource.id,
                expectedType: resource.type,
                context: "\(context) included resource"
            )
            let identity = "\(resource.type):\(resource.id)"
            guard identities.insert(identity).inserted else {
                throw PromotedPurchaseInputError(
                    "Apple returned a duplicate included resource in \(context)"
                )
            }
            if !expectedIdentities.contains(identity) {
                throw PromotedPurchaseInputError(
                    "Apple returned an unrelated included resource in \(context)"
                )
            }
        }
    }

    private func promotedPurchaseOrder(appID: String, context: String) async throws -> [String] {
        let path = "/v1/apps/\(try ASCPathSegment.encode(appID, field: "app_id"))/relationships/promotedPurchases"
        let query = ["limit": "200"]
        let scope = PaginationScope.strict(path: path, query: query)
        var order: [String] = []
        var identities = Set<String>()
        var seenContinuations = Set<String>()
        var nextURL: String?
        var stableTotal: Int?
        var pageNumber = 0

        repeat {
            pageNumber += 1
            guard pageNumber <= 100 else {
                throw PromotedPurchaseInputError(
                    "Apple returned more than 100 promoted purchase relationship pages in \(context)"
                )
            }
            let response: ASCPromotedPurchaseLinkagesResponse
            let currentPageRequest: PaginationRequest?
            if let nextURL {
                guard seenContinuations.insert(nextURL).inserted else {
                    throw PromotedPurchaseInputError(
                        "Apple repeated a promoted purchase continuation URL in \(context)"
                    )
                }
                currentPageRequest = try httpClient.validatedScopedLink(
                    nextURL,
                    scope: scope
                )
                response = try await httpClient.getPage(
                    nextURL,
                    scope: scope,
                    as: ASCPromotedPurchaseLinkagesResponse.self
                )
            } else {
                currentPageRequest = nil
                response = try await httpClient.get(
                    path,
                    parameters: query,
                    as: ASCPromotedPurchaseLinkagesResponse.self
                )
            }
            let pageTotal = try validatePromotedLinkagePage(
                response,
                expectedPath: path,
                expectedCursor: currentPageRequest?.parameters["cursor"],
                context: context
            )
            if let pageTotal {
                if let stableTotal, stableTotal != pageTotal {
                    throw PromotedPurchaseInputError(
                        "Apple changed the promoted purchase paging total in \(context)"
                    )
                }
                stableTotal = pageTotal
            }
            for resource in response.data {
                guard identities.insert(resource.id).inserted else {
                    throw PromotedPurchaseInputError(
                        "Apple returned duplicate promoted purchase linkage in \(context)"
                    )
                }
                order.append(resource.id)
            }
            if let stableTotal, order.count > stableTotal {
                throw PromotedPurchaseInputError(
                    "Apple returned more promoted purchase linkages than its paging total in \(context)"
                )
            }
            nextURL = response.links.next
        } while nextURL != nil

        if let stableTotal, order.count != stableTotal {
            throw PromotedPurchaseInputError(
                "Apple returned \(order.count) promoted purchase linkages but declared total \(stableTotal) in \(context)"
            )
        }
        return order
    }

    private func validatePromotedLinkagePage(
        _ response: ASCPromotedPurchaseLinkagesResponse,
        expectedPath: String,
        expectedCursor: String?,
        context: String
    ) throws -> Int? {
        var selfQuery = ["limit": "200"]
        if let expectedCursor {
            selfQuery["cursor"] = expectedCursor
        }
        let selfRequest = try validatePromotedDocumentSelf(
            response.links.`self`,
            expectedPath: expectedPath,
            requiredQuery: selfQuery,
            allowedQueryNames: Set(selfQuery.keys),
            requiresCursor: expectedCursor != nil,
            context: context
        )
        let nextRequest = try validatePromotedNextPageLink(
            response.links.next,
            scope: PaginationScope.strict(
                path: expectedPath,
                query: ["limit": "200"]
            ),
            currentCursor: selfRequest.parameters["cursor"],
            context: context
        )
        let total = try validatePromotedPaging(
            response.meta,
            expectedLimit: 200,
            pageCount: response.data.count,
            nextRequest: nextRequest,
            context: context
        )
        for resource in response.data {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: resource.type,
                id: resource.id,
                expectedType: "promotedPurchases",
                context: "\(context) linkage"
            )
        }
        return total
    }

    @discardableResult
    private func validatePromotedDocumentSelf(
        _ value: String,
        expectedPath: String,
        requiredQuery: [String: String] = [:],
        allowedQueryNames: Set<String> = [],
        requiresCursor: Bool = false,
        context: String
    ) throws -> PaginationRequest {
        let request: PaginationRequest
        do {
            request = try httpClient.validatedScopedLink(
                value,
                scope: PaginationScope(
                    path: expectedPath,
                    requiredParameters: requiredQuery,
                    allowedParameters: allowedQueryNames,
                    requiredNonEmptyParameters: requiresCursor ? ["cursor"] : []
                )
            )
        } catch {
            throw PromotedPurchaseInputError(
                "Apple returned an invalid required links.self in \(context): \(error.localizedDescription)"
            )
        }
        if !requiresCursor, request.parameters["cursor"] != nil {
            throw PromotedPurchaseInputError(
                "Apple returned an unexpected cursor in first-page links.self for \(context)"
            )
        }
        return request
    }

    private func validatePromotedNextPageLink(
        _ value: String?,
        scope: PaginationScope,
        currentCursor: String?,
        context: String
    ) throws -> PaginationRequest? {
        guard let value else { return nil }
        let request: PaginationRequest
        do {
            request = try httpClient.validatedScopedLink(value, scope: scope)
        } catch {
            throw PromotedPurchaseInputError(
                "Apple returned an invalid links.next in \(context): \(error.localizedDescription)"
            )
        }
        guard let cursor = request.parameters["cursor"],
              !cursor.isEmpty,
              cursor == cursor.trimmingCharacters(in: .whitespacesAndNewlines),
              cursor != currentCursor else {
            throw PromotedPurchaseInputError(
                "Apple returned a non-advancing pagination cursor in \(context)"
            )
        }
        return request
    }

    private func validatePromotedPaging(
        _ meta: ASCPagingInformation?,
        expectedLimit: Int,
        pageCount: Int,
        nextRequest: PaginationRequest?,
        context: String
    ) throws -> Int? {
        guard pageCount <= expectedLimit else {
            throw PromotedPurchaseInputError(
                "Apple returned more resources than the requested limit in \(context)"
            )
        }
        guard let meta else { return nil }
        guard let paging = meta.paging,
              paging.limit == expectedLimit else {
            throw PromotedPurchaseInputError(
                "Apple returned invalid paging limit metadata in \(context)"
            )
        }
        if let total = paging.total {
            guard total >= 0, total >= pageCount else {
                throw PromotedPurchaseInputError(
                    "Apple returned paging total below the page count in \(context)"
                )
            }
        }

        let linkedCursor = nextRequest?.parameters["cursor"]
        switch (paging.nextCursor, linkedCursor) {
        case (nil, nil):
            break
        case let (metadataCursor?, nextCursor?)
            where !metadataCursor.isEmpty
                && metadataCursor == metadataCursor.trimmingCharacters(in: .whitespacesAndNewlines)
                && metadataCursor == nextCursor:
            break
        default:
            throw PromotedPurchaseInputError(
                "Apple returned inconsistent paging cursor metadata in \(context)"
            )
        }
        return paging.total
    }

    private func promotedCreateFailure(
        error: Error,
        phase: ASCNonIdempotentWriteFailurePhase,
        appID: String,
        visible: Bool,
        enabled: Value?,
        iapID: String?,
        subscriptionID: String?
    ) -> CallTool.Result {
        var identifiers: [String: Value] = [
            "app_id": .string(appID),
            "visible": .bool(visible)
        ]
        if let enabled {
            identifiers["enabled"] = enabled
        }
        if let iapID {
            identifiers["iap_id"] = .string(iapID)
        }
        if let subscriptionID {
            identifiers["subscription_id"] = .string(subscriptionID)
        }
        let baseDetails = ASCNonIdempotentWriteRecovery.failureDetails(
            for: error,
            phase: phase,
            operation: "promoted_create",
            identifiers: identifiers,
            listTool: "promoted_list",
            listArguments: ["app_id": .string(appID), "limit": .int(200)],
            getTool: "promoted_get",
            getIDArgument: "promoted_purchase_id",
            listResultIDPath: "promoted_purchases[].id",
            matchingFields: []
        )
        let details = promotedCreateRecoveryDetails(
            baseDetails,
            appID: appID,
            identifiers: identifiers
        )
        return promotedFailureResult(
            message: "Failed to create promoted purchase: \(error.localizedDescription)",
            details: details
        )
    }

    private func promotedCreateRecoveryDetails(
        _ value: Value,
        appID: String,
        identifiers: [String: Value]
    ) -> Value {
        guard case .object(var details) = value,
              case .object(var recovery) = details["recovery"] else {
            return value
        }

        let outputFields = [
            "visible": "visibleForAllUsers",
            "enabled": "enabled",
            "iap_id": "inAppPurchaseId",
            "subscription_id": "subscriptionId"
        ]
        let fieldMappings = outputFields.keys.sorted().compactMap { requestField -> Value? in
            guard let requestValue = identifiers[requestField],
                  let outputField = outputFields[requestField] else {
                return nil
            }
            return .object([
                "request_field": .string(requestField),
                "request_value": requestValue,
                "output_field": .string(outputField)
            ])
        }
        var requestValues = identifiers
        requestValues.removeValue(forKey: "app_id")
        recovery["candidate_scope"] = .object([
            "request_field": .string("app_id"),
            "list_argument": .string("app_id"),
            "value": .string(appID),
            "instruction": .string(
                "The candidate list is scoped to the requested app; app_id is not a promoted_list result field."
            )
        ])
        recovery["match_requested"] = .object([
            "field_mappings": .array(fieldMappings),
            "request_values": .object(requestValues),
            "instruction": .string(
                "Compare each request value with its mapped promoted_list output field. For a requested null clear, inspect the exact candidate because the response Boolean may be omitted."
            )
        ])
        details["recovery"] = .object(recovery)
        return .object(details)
    }

    private func promotedRequestedUpdateArguments(
        _ arguments: [String: Value]
    ) -> [String: Value] {
        var requested: [String: Value] = [
            "promoted_purchase_id": arguments["promoted_purchase_id"] ?? .null
        ]
        if let visible = arguments["visible"] {
            requested["visible"] = visible
        }
        if let enabled = arguments["enabled"] {
            requested["enabled"] = enabled
        }
        return requested
    }

    private func promotedTargetMutationFailure(
        operation: String,
        targetID: String,
        requestedArguments: [String: Value],
        error: Error,
        phase: ASCNonIdempotentWriteFailurePhase
    ) -> CallTool.Result {
        let details = promotedMutationFailureDetails(
            operation: operation,
            identifiers: [
                "promoted_purchase_id": .string(targetID),
                "requestedArguments": .object(requestedArguments)
            ],
            error: error,
            phase: phase,
            recovery: .object([
                "inspect_target": .object([
                    "tool": .string("promoted_get"),
                    "arguments": .object([
                        "promoted_purchase_id": .string(targetID)
                    ]),
                    "instruction": .string(
                        "Inspect the exact promoted purchase before retrying the mutation."
                    )
                ])
            ])
        )
        return promotedFailureResult(
            message: "Failed to update promoted purchase: \(error.localizedDescription)",
            details: details
        )
    }

    private func promotedReorderFailure(
        appID: String,
        requestedOrder: [String],
        preflightOrder: [String],
        error: Error,
        phase: ASCNonIdempotentWriteFailurePhase
    ) -> CallTool.Result {
        let details = promotedMutationFailureDetails(
            operation: "promoted_reorder",
            identifiers: [
                "app_id": .string(appID),
                "requestedOrder": .array(requestedOrder.map(Value.string)),
                "preflightOrder": .array(preflightOrder.map(Value.string))
            ],
            error: error,
            phase: phase,
            recovery: .object([
                "inspect_order": .object([
                    "tool": .string("promoted_list"),
                    "arguments": .object([
                        "app_id": .string(appID),
                        "limit": .int(200)
                    ]),
                    "continue_with_next_url": .bool(true),
                    "instruction": .string(
                        "Inspect every page and compare promoted_purchases[].id with requestedOrder before retrying."
                    )
                ])
            ])
        )
        return promotedFailureResult(
            message: "Failed to verify promoted purchase reorder: \(error.localizedDescription)",
            details: details
        )
    }

    private func promotedMutationFailureDetails(
        operation: String,
        identifiers: [String: Value],
        error: Error,
        phase: ASCNonIdempotentWriteFailurePhase,
        recovery: Value
    ) -> Value {
        let disposition = ASCNonIdempotentWriteRecovery.failureDisposition(
            for: error,
            phase: phase
        )
        var details = identifiers
        details["operation"] = .string(operation)
        details["write_outcome"] = .string(disposition.rawValue)
        details["operationCommitState"] = .string(disposition.rawValue)
        details["retrySafe"] = .bool(false)
        details["cause"] = promotedMutationCause(error, phase: phase)
        guard disposition != .rejected else {
            return .object(details)
        }
        details["inspectionRequired"] = .bool(true)
        details["recovery"] = recovery
        switch disposition {
        case .rejected:
            break
        case .outcomeUnknown:
            details["outcomeUnknown"] = .bool(true)
        case .committedUnverified:
            details["operationCommitted"] = .bool(true)
            details["outcomeUnknown"] = .bool(false)
        }
        return .object(details)
    }

    private func promotedMutationCause(
        _ error: Error,
        phase: ASCNonIdempotentWriteFailurePhase
    ) -> Value {
        if let ascError = error as? ASCError {
            return ascError.structuredValue
        }
        if error is CancellationError {
            return .object([
                "type": .string("cancellation"),
                "message": .string(
                    "The request was cancelled before its write outcome was confirmed"
                )
            ])
        }
        return .object([
            "type": .string(phase == .request ? "request" : "response_validation"),
            "message": .string(Redactor.redact(error.localizedDescription))
        ])
    }

    private func promotedAcceptedMutationError(
        _ error: Error,
        method: String,
        expectedStatusCode: Int,
        actualStatusCode: Int
    ) -> ASCError {
        let cause: ASCError
        if let ascError = error as? ASCError {
            if case .mutationCommittedUnverified = ascError {
                return ascError
            }
            cause = ascError
        } else {
            cause = .parsing(Redactor.redact(error.localizedDescription))
        }
        return .mutationCommittedUnverified(
            method: method,
            expectedStatusCode: expectedStatusCode,
            actualStatusCode: actualStatusCode,
            cause: cause
        )
    }

    private func promotedDeleteFailure(targetID: String, error: Error) -> CallTool.Result {
        let deletionState: String
        let operationCommitState: String
        let outcomeUnknown: Bool
        let operationCommitted: Bool
        let inspectionRequired: Bool
        switch error as? ASCError {
        case .deleteCommittedUnverified:
            deletionState = "committed_unverified"
            operationCommitState = "committed_unverified"
            outcomeUnknown = false
            operationCommitted = true
            inspectionRequired = true
        case .deleteOutcomeUnknown:
            deletionState = "commit_unknown"
            operationCommitState = "unknown"
            outcomeUnknown = true
            operationCommitted = false
            inspectionRequired = true
        default:
            deletionState = "rejected"
            operationCommitState = "rejected"
            outcomeUnknown = false
            operationCommitted = false
            inspectionRequired = false
        }

        var details: [String: Value] = [
            "operation": .string("promoted_delete"),
            "promoted_purchase_id": .string(targetID),
            "deletionState": .string(deletionState),
            "operationCommitState": .string(operationCommitState),
            "operationCommitted": .bool(operationCommitted),
            "outcomeUnknown": .bool(outcomeUnknown),
            "inspectionRequired": .bool(inspectionRequired),
            "retrySafe": .bool(false),
            "cause": promotedMutationCause(error, phase: .request)
        ]
        if inspectionRequired {
            details["recovery"] = .object([
                "inspect_target": .object([
                    "tool": .string("promoted_get"),
                    "arguments": .object([
                        "promoted_purchase_id": .string(targetID)
                    ]),
                    "instruction": .string(
                        "Inspect the exact target before another delete attempt."
                    )
                ])
            ])
        }
        return promotedFailureResult(
            message: "Failed to delete promoted purchase: \(error.localizedDescription)",
            details: .object(details)
        )
    }

    private func promotedFailureResult(message: String, details: Value) -> CallTool.Result {
        let redactedMessage = Redactor.redact(message)
        var root: [String: Value] = [
            "success": .bool(false),
            "error": .string(redactedMessage),
            "details": details
        ]
        if case .object(let object) = details {
            for key in [
                "operationCommitState",
                "operationCommitted",
                "outcomeUnknown",
                "inspectionRequired",
                "retrySafe",
                "deletionState"
            ] where object[key] != nil {
                root[key] = object[key]
            }
        }
        return MCPResult.json(
            .object(root),
            text: "Error: \(redactedMessage)",
            isError: true
        )
    }

    private func formatPromotedPurchase(
        _ purchase: ASCPromotedPurchase,
        included: [PromotedPurchaseIncludedResource]? = nil
    ) -> [String: Any] {
        var result: [String: Any] = [
            "id": purchase.id,
            "type": purchase.type,
            "visibleForAllUsers": (purchase.attributes?.visibleForAllUsers).jsonSafe,
            "enabled": (purchase.attributes?.enabled).jsonSafe,
            "state": (purchase.attributes?.state).jsonSafe
        ]

        result["inAppPurchaseId"] = (purchase.relationships?.inAppPurchaseV2?.data?.id).jsonSafe
        result["subscriptionId"] = (purchase.relationships?.subscription?.data?.id).jsonSafe

        let linkedIdentity = purchase.relationships?.inAppPurchaseV2?.data
            ?? purchase.relationships?.subscription?.data
        let linkedResource = included?.first(where: { resource in
            guard let linkedIdentity else { return false }
            return resource.type == linkedIdentity.type && resource.id == linkedIdentity.id
        })
        if let resource = linkedResource {
            result["linkedProduct"] = [
                "type": resource.type,
                "id": resource.id,
                "name": (resource.attributes?.name).jsonSafe,
                "productId": (resource.attributes?.productId).jsonSafe
            ] as [String: Any]
        }

        return result
    }

    private func nullableBool(
        _ name: String,
        from arguments: [String: Value]
    ) throws -> PromotedPurchaseNullableBool? {
        guard let value = arguments[name] else {
            return nil
        }
        if value.isNull {
            return .null
        }
        guard let bool = value.boolValue else {
            throw PromotedPurchaseInputError("Parameter '\(name)' must be a boolean or null")
        }
        return .value(bool)
    }

    private func promotedPurchasePaginationScope(path: String, query: [String: String]) -> PaginationScope {
        PaginationScope(
            path: path,
            requiredParameters: query,
            allowedParameters: Set(query.keys).union(["cursor"]),
            requiredNonEmptyParameters: ["cursor"]
        )
    }
}

private struct PromotedPurchaseInputError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
