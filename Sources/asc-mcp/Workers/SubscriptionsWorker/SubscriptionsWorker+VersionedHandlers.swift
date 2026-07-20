import Foundation
import MCP

extension SubscriptionsWorker {
    func createSubscriptionVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments: [String: Value]
        let subscriptionID: String
        do {
            arguments = try subscriptionVersionedArguments(params.arguments, allowed: ["subscription_id"])
            subscriptionID = try subscriptionVersionedCanonicalIdentifier("subscription_id", arguments: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription version creation")
        }

        let body: Data
        do {
            _ = try ASCPathSegment.encode(subscriptionID, field: "subscription_id")
            body = try JSONEncoder().encode(CreateSubscriptionVersionRequest(subscriptionID: subscriptionID))
        } catch {
            return MCPResult.error("Failed to create subscription version: \(error.localizedDescription)")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/subscriptionVersions", body: body)
        } catch {
            return MCPResult.error(
                "Failed to create subscription version: \(error.localizedDescription)",
                details: ASCNonIdempotentWriteRecovery.failureDetails(
                    for: error,
                    phase: .request,
                    operation: "subscriptions_create_version",
                    identifiers: ["subscription_id": .string(subscriptionID)],
                    listTool: "subscriptions_list_versions",
                    listArguments: ["subscription_id": .string(subscriptionID), "limit": .int(200)],
                    getTool: "subscriptions_get_version",
                    getIDArgument: "version_id",
                    listResultIDPath: "versions[].id",
                    matchingFields: ["subscription_id"]
                )
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Subscription version create"
            )
            let response = try JSONDecoder().decode(ASCSubscriptionVersionResponse.self, from: receipt.data)
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: "/v1/subscriptionVersions/\(try ASCPathSegment.encode(response.data.id))",
                context: "Apple subscription version create response"
            )
            try validateSubscriptionVersionResource(
                response.data,
                expectedSubscriptionID: subscriptionID,
                context: "Apple subscription version create response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "version": formatSubscriptionVersion(response.data)
            ])
        } catch {
            return MCPResult.error(
                "Failed to create subscription version: \(error.localizedDescription)",
                details: ASCNonIdempotentWriteRecovery.failureDetails(
                    for: error,
                    phase: .acceptedResponse,
                    operation: "subscriptions_create_version",
                    identifiers: ["subscription_id": .string(subscriptionID)],
                    listTool: "subscriptions_list_versions",
                    listArguments: ["subscription_id": .string(subscriptionID), "limit": .int(200)],
                    getTool: "subscriptions_get_version",
                    getIDArgument: "version_id",
                    listResultIDPath: "versions[].id",
                    matchingFields: ["subscription_id"]
                )
            )
        }
    }

    func getSubscriptionVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let versionID: String
        do {
            let arguments = try subscriptionVersionedArguments(params.arguments, allowed: ["version_id"])
            versionID = try subscriptionVersionedCanonicalIdentifier("version_id", arguments: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription version lookup")
        }

        do {
            let endpoint = "/v1/subscriptionVersions/\(try ASCPathSegment.encode(versionID, field: "version_id"))"
            let data = try await httpClient.get(endpoint)
            let response = try JSONDecoder().decode(ASCSubscriptionVersionResponse.self, from: data)
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: endpoint,
                context: "Apple subscription version get response"
            )
            try validateSubscriptionVersionResource(
                response.data,
                expectedID: versionID,
                context: "Apple subscription version get response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "version": formatSubscriptionVersion(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get subscription version")
        }
    }

    func listSubscriptionVersions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments: [String: Value]
        let subscriptionID: String
        do {
            arguments = try subscriptionVersionedArguments(
                params.arguments,
                allowed: ["subscription_id", "filter_state", "limit", "next_url"]
            )
            subscriptionID = try subscriptionVersionedCanonicalIdentifier("subscription_id", arguments: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription versions list")
        }

        do {
            let endpoint = "/v1/subscriptions/\(try ASCPathSegment.encode(subscriptionID, field: "subscription_id"))/versions"
            var query = ["limit": String(try subscriptionVersionedLimit(arguments["limit"]))]
            if let states = try subscriptionCatalogQueryValue(
                arguments["filter_state"],
                field: "filter_state",
                allowedValues: Set(Self.subscriptionVersionStates)
            ) {
                query["filter[state]"] = states
            }

            let response: ASCSubscriptionVersionsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: subscriptionCommercePaginationScope(path: endpoint, query: query),
                    as: ASCSubscriptionVersionsResponse.self
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: query, as: ASCSubscriptionVersionsResponse.self)
            }
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: endpoint,
                context: "Apple subscription versions list response"
            )
            try validateSubscriptionVersionCollection(
                response.data,
                expectedSubscriptionID: subscriptionID,
                context: "Apple subscription versions list response"
            )
            try validateSubscriptionPagingInformation(
                response.meta,
                resourceCount: response.data.count,
                nextLink: response.links.next,
                validatesContinuation: true,
                context: "Apple subscription versions list response"
            )

            var result: [String: Any] = [
                "success": true,
                "versions": response.data.map(formatSubscriptionVersion),
                "count": response.data.count,
                "total": response.meta?.paging?.total.jsonSafe
            ]
            if let nextURL = response.links.next {
                result["next_url"] = nextURL
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list subscription versions")
        }
    }

    func listSubscriptionVersionLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments: [String: Value]
        let versionID: String
        do {
            arguments = try subscriptionVersionedArguments(
                params.arguments,
                allowed: ["version_id", "limit", "next_url"]
            )
            versionID = try subscriptionVersionedCanonicalIdentifier("version_id", arguments: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription version localizations list")
        }

        do {
            let endpoint = "/v1/subscriptionVersions/\(try ASCPathSegment.encode(versionID, field: "version_id"))/localizations"
            let query = ["limit": String(try subscriptionVersionedLimit(arguments["limit"]))]
            let response: ASCSubscriptionVersionLocalizationsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: subscriptionCommercePaginationScope(path: endpoint, query: query),
                    as: ASCSubscriptionVersionLocalizationsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCSubscriptionVersionLocalizationsResponse.self
                )
            }
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: endpoint,
                context: "Apple subscription version localizations list response"
            )
            try validateSubscriptionVersionLocalizationCollection(
                response.data,
                expectedVersionID: versionID,
                context: "Apple subscription version localizations list response"
            )
            try validateSubscriptionPagingInformation(
                response.meta,
                resourceCount: response.data.count,
                nextLink: response.links.next,
                validatesContinuation: true,
                context: "Apple subscription version localizations list response"
            )

            var result: [String: Any] = [
                "success": true,
                "localizations": response.data.map(formatSubscriptionVersionLocalization),
                "count": response.data.count,
                "total": response.meta?.paging?.total.jsonSafe
            ]
            if let nextURL = response.links.next {
                result["next_url"] = nextURL
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list subscription version localizations")
        }
    }

    func createSubscriptionVersionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments: [String: Value]
        let versionID: String
        let locale: String
        let name: String
        do {
            arguments = try subscriptionVersionedArguments(
                params.arguments,
                allowed: ["version_id", "locale", "name", "description"]
            )
            versionID = try subscriptionVersionedCanonicalIdentifier("version_id", arguments: arguments)
            guard let localeValue = arguments["locale"]?.stringValue,
                  let nameValue = arguments["name"]?.stringValue else {
                throw ASCError.parsing("Required parameters: version_id, locale, name")
            }
            try requireNonEmptySubscriptionVersionedString(localeValue, field: "locale")
            try requireNonEmptySubscriptionVersionedString(nameValue, field: "name")
            locale = localeValue
            name = nameValue
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription version localization creation")
        }
        let validationErrors = subscriptionVersionedMetadataValidationErrors(
            arguments,
            locale: locale
        )
        guard validationErrors.isEmpty else {
            return ASCMetadataValidator.errorResult(validationErrors)
        }

        let body: Data
        var identifiers: [String: Value] = [
            "version_id": .string(versionID),
            "locale": .string(locale),
            "name": .string(name)
        ]
        if let description = arguments["description"] {
            identifiers["description"] = description
        }

        do {
            _ = try ASCPathSegment.encode(versionID, field: "version_id")
            try requireNonEmptySubscriptionVersionedString(locale, field: "locale")
            try requireNonEmptySubscriptionVersionedString(name, field: "name")
            let request = CreateSubscriptionVersionLocalizationRequest(
                versionID: versionID,
                locale: locale,
                name: name,
                description: try subscriptionVersionedNullableString("description", arguments: arguments)
            )
            body = try JSONEncoder().encode(request)
        } catch {
            return MCPResult.error(error, prefix: "Failed to create subscription version localization")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v2/subscriptionLocalizations", body: body)
        } catch {
            return MCPResult.error(
                "Failed to create subscription version localization: \(error.localizedDescription)",
                details: ASCNonIdempotentWriteRecovery.failureDetails(
                    for: error,
                    phase: .request,
                    operation: "subscriptions_create_version_localization",
                    identifiers: identifiers,
                    listTool: "subscriptions_list_version_localizations",
                    listArguments: ["version_id": .string(versionID), "limit": .int(200)],
                    getTool: "subscriptions_get_version_localization",
                    getIDArgument: "localization_id",
                    listResultIDPath: "localizations[].id",
                    matchingFields: ["version_id", "locale", "name", "description"]
                )
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Subscription version localization create"
            )
            let response = try JSONDecoder().decode(
                ASCSubscriptionVersionLocalizationResponse.self,
                from: receipt.data
            )
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: "/v2/subscriptionLocalizations/\(try ASCPathSegment.encode(response.data.id))",
                context: "Apple subscription version localization create response"
            )
            try validateSubscriptionVersionLocalizationResource(
                response.data,
                expectedVersionID: versionID,
                context: "Apple subscription version localization create response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "localization": formatSubscriptionVersionLocalization(response.data)
            ])
        } catch {
            return MCPResult.error(
                "Failed to create subscription version localization: \(error.localizedDescription)",
                details: ASCNonIdempotentWriteRecovery.failureDetails(
                    for: error,
                    phase: .acceptedResponse,
                    operation: "subscriptions_create_version_localization",
                    identifiers: identifiers,
                    listTool: "subscriptions_list_version_localizations",
                    listArguments: ["version_id": .string(versionID), "limit": .int(200)],
                    getTool: "subscriptions_get_version_localization",
                    getIDArgument: "localization_id",
                    listResultIDPath: "localizations[].id",
                    matchingFields: ["version_id", "locale", "name", "description"]
                )
            )
        }
    }

    func getSubscriptionVersionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let localizationID: String
        do {
            let arguments = try subscriptionVersionedArguments(params.arguments, allowed: ["localization_id"])
            localizationID = try subscriptionVersionedCanonicalIdentifier("localization_id", arguments: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription version localization lookup")
        }

        do {
            let endpoint = "/v2/subscriptionLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))"
            let data = try await httpClient.get(endpoint)
            let response = try JSONDecoder().decode(ASCSubscriptionVersionLocalizationResponse.self, from: data)
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: endpoint,
                context: "Apple subscription version localization get response"
            )
            try validateSubscriptionVersionLocalizationResource(
                response.data,
                expectedID: localizationID,
                context: "Apple subscription version localization get response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "localization": formatSubscriptionVersionLocalization(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get subscription version localization")
        }
    }

    func updateSubscriptionVersionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments: [String: Value]
        let localizationID: String
        do {
            arguments = try subscriptionVersionedArguments(
                params.arguments,
                allowed: ["localization_id", "name", "description"]
            )
            localizationID = try subscriptionVersionedCanonicalIdentifier("localization_id", arguments: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription version localization update")
        }
        guard arguments["name"] != nil || arguments["description"] != nil else {
            return MCPResult.error("At least one of name or description is required")
        }
        let validationErrors = subscriptionVersionedMetadataValidationErrors(arguments)
        guard validationErrors.isEmpty else {
            return ASCMetadataValidator.errorResult(validationErrors)
        }
        var requestedArguments: [String: Value] = ["localization_id": .string(localizationID)]
        if let name = arguments["name"] {
            requestedArguments["name"] = name
        }
        if let description = arguments["description"] {
            requestedArguments["description"] = description
        }

        let endpoint: String
        let body: Data
        do {
            endpoint = "/v2/subscriptionLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))"
            let request = UpdateSubscriptionVersionLocalizationRequest(
                localizationID: localizationID,
                name: try subscriptionVersionedNullableString("name", arguments: arguments),
                description: try subscriptionVersionedNullableString("description", arguments: arguments)
            )
            body = try JSONEncoder().encode(request)
        } catch {
            return MCPResult.error(error, prefix: "Failed to update subscription version localization")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(endpoint, body: body)
        } catch {
            return subscriptionMutationRequestFailure(
                operation: "subscriptions_update_version_localization",
                action: "subscription version localization update",
                targetField: "localization_id",
                targetID: localizationID,
                requestedArguments: requestedArguments,
                error: error,
                inspectionTool: "subscriptions_get_version_localization"
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 200,
                context: "Subscription version localization update"
            )
            let response = try JSONDecoder().decode(
                ASCSubscriptionVersionLocalizationResponse.self,
                from: receipt.data
            )
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: endpoint,
                context: "Apple subscription version localization update response"
            )
            try validateSubscriptionVersionLocalizationResource(
                response.data,
                expectedID: localizationID,
                context: "Apple subscription version localization update response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "localization": formatSubscriptionVersionLocalization(response.data)
            ])
        } catch {
            return subscriptionCommittedUnverifiedMutationFailure(
                operation: "subscriptions_update_version_localization",
                targetField: "localization_id",
                targetID: localizationID,
                requestedArguments: requestedArguments,
                error: error,
                inspectionTool: "subscriptions_get_version_localization"
            )
        }
    }

    func deleteSubscriptionVersionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let localizationID: String
        let endpoint: String
        do {
            let arguments = try subscriptionVersionedArguments(
                params.arguments,
                allowed: ["localization_id", "confirm_localization_id"]
            )
            localizationID = try subscriptionVersionedCanonicalIdentifier("localization_id", arguments: arguments)
            let confirmation = try subscriptionVersionedCanonicalIdentifier(
                "confirm_localization_id",
                arguments: arguments
            )
            guard confirmation == localizationID else {
                return MCPResult.error(
                    "Deleting a subscription version localization is irreversible. Set confirm_localization_id to the exact localization_id to continue."
                )
            }
            endpoint = "/v2/subscriptionLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))"
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription version localization deletion")
        }

        do {
            _ = try await httpClient.delete(endpoint)
            return MCPResult.jsonObject([
                "success": true,
                "localization_id": localizationID,
                "deleted": true,
                "deletionState": "confirmed",
                "outcomeUnknown": false,
                "retrySafe": false
            ])
        } catch {
            return subscriptionVersionedDeletionFailure(
                resourceName: "subscription version localization",
                targetField: "localization_id",
                targetID: localizationID,
                error: error,
                inspectionTool: "subscriptions_get_version_localization"
            )
        }
    }

    func listSubscriptionVersionImages(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments: [String: Value]
        let versionID: String
        do {
            arguments = try subscriptionVersionedArguments(
                params.arguments,
                allowed: ["version_id", "limit", "next_url"]
            )
            versionID = try subscriptionVersionedCanonicalIdentifier("version_id", arguments: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription version images list")
        }

        do {
            let endpoint = "/v1/subscriptionVersions/\(try ASCPathSegment.encode(versionID, field: "version_id"))/images"
            let query = ["limit": String(try subscriptionVersionedLimit(arguments["limit"]))]
            let response: ASCSubscriptionVersionImagesResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: subscriptionCommercePaginationScope(path: endpoint, query: query),
                    as: ASCSubscriptionVersionImagesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCSubscriptionVersionImagesResponse.self
                )
            }
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: endpoint,
                context: "Apple subscription version images list response"
            )
            try validateSubscriptionVersionImageCollection(
                response.data,
                context: "Apple subscription version images list response"
            )
            try validateSubscriptionPagingInformation(
                response.meta,
                resourceCount: response.data.count,
                nextLink: response.links.next,
                validatesContinuation: true,
                context: "Apple subscription version images list response"
            )

            var result: [String: Any] = [
                "success": true,
                "images": response.data.map(formatSubscriptionVersionImage),
                "count": response.data.count,
                "total": response.meta?.paging?.total.jsonSafe
            ]
            if let nextURL = response.links.next {
                result["next_url"] = nextURL
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list subscription version images")
        }
    }

    func uploadSubscriptionVersionImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let versionID: String
        let filePath: String
        do {
            let arguments = try subscriptionVersionedArguments(
                params.arguments,
                allowed: ["version_id", "file_path"]
            )
            versionID = try subscriptionVersionedCanonicalIdentifier("version_id", arguments: arguments)
            guard let path = arguments["file_path"]?.stringValue,
                  !path.isEmpty,
                  path == path.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw ASCError.parsing("'file_path' must be a non-empty path")
            }
            guard (path as NSString).isAbsolutePath else {
                throw ASCError.parsing("'file_path' must be an absolute path")
            }
            filePath = path
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription version image upload")
        }

        do {
            _ = try ASCPathSegment.encode(versionID, field: "version_id")
        } catch {
            return MCPResult.error(error, prefix: "Failed to upload subscription version image")
        }

        let outcome: UploadTransactionOutcome<ASCSubscriptionVersionImage> = await UploadTransactionRecovery.perform(
            filePath: filePath,
            resourceName: "subscription version image",
            expectedType: "subscriptionImages",
            reservationEndpoint: "/v2/subscriptionImages",
            httpClient: httpClient,
            uploadService: uploadService,
            validateReservedResource: { image, snapshot in
                try validateSubscriptionVersionImageResource(
                    image,
                    context: "Apple subscription version image upload response"
                )
                guard image.attributes?.fileName == snapshot.fileName,
                      image.attributes?.fileSize == snapshot.fileSize else {
                    throw ASCError.parsing(
                        "Apple's subscription version image reservation does not match the immutable file snapshot"
                    )
                }
                guard case .pending(let state) = image.recoveryDeliveryStatus,
                      state == "AWAITING_UPLOAD" else {
                    throw ASCError.parsing(
                        "Apple's subscription version image reservation is not awaiting upload"
                    )
                }
            },
            deliveryPollAttempts: deliveryPollAttempts,
            deliveryPollIntervalNanoseconds: deliveryPollIntervalNanoseconds,
            makeReservationBody: { fileSize, fileName in
                try JSONEncoder().encode(
                    CreateSubscriptionVersionImageRequest(
                        versionID: versionID,
                        fileSize: fileSize,
                        fileName: fileName
                    )
                )
            },
            decodeResource: {
                let response = try JSONDecoder().decode(ASCSubscriptionVersionImageResponse.self, from: $0)
                let expectedPath = "/v2/subscriptionImages/\(try ASCPathSegment.encode(response.data.id, field: "image_id"))"
                try validateSubscriptionDocumentSelfLink(
                    response.links.`self`,
                    expectedPath: expectedPath,
                    context: "Apple subscription version image upload response"
                )
                return response.data
            },
            makeCommitBody: { imageID, _ in
                try JSONEncoder().encode(CommitSubscriptionVersionImageRequest(imageID: imageID))
            },
            resourceEndpoint: {
                "/v2/subscriptionImages/\(try ASCPathSegment.encode($0, field: "image_id"))"
            }
        )

        return UploadTransactionRecovery.result(
            for: outcome,
            descriptor: UploadRecoveryDescriptor(
                resourceName: "subscription version image",
                successKey: "image",
                idArgument: "image_id",
                getTool: "subscriptions_get_version_image",
                getIDArgument: "image_id",
                deleteTool: "subscriptions_delete_version_image",
                deleteConfirmationArgument: "confirm_image_id",
                inspectionTool: "subscriptions_list_version_images",
                inspectionArguments: ["version_id": versionID],
                inspectionPageLimit: 200,
                inspectionNextURLArgument: "next_url",
                reservationFingerprintKey: "reservationFingerprint",
                inspectionCandidateFields: ["file_name", "file_size"]
            ),
            format: formatSubscriptionVersionImage
        )
    }

    func getSubscriptionVersionImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let imageID: String
        do {
            let arguments = try subscriptionVersionedArguments(params.arguments, allowed: ["image_id"])
            imageID = try subscriptionVersionedCanonicalIdentifier("image_id", arguments: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription version image lookup")
        }

        do {
            let endpoint = "/v2/subscriptionImages/\(try ASCPathSegment.encode(imageID, field: "image_id"))"
            let data = try await httpClient.get(endpoint)
            let response = try JSONDecoder().decode(ASCSubscriptionVersionImageResponse.self, from: data)
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: endpoint,
                context: "Apple subscription version image get response"
            )
            try validateSubscriptionVersionImageResource(
                response.data,
                expectedID: imageID,
                context: "Apple subscription version image get response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "image": formatSubscriptionVersionImage(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get subscription version image")
        }
    }

    func deleteSubscriptionVersionImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let imageID: String
        let endpoint: String
        do {
            let arguments = try subscriptionVersionedArguments(
                params.arguments,
                allowed: ["image_id", "confirm_image_id"]
            )
            imageID = try subscriptionVersionedCanonicalIdentifier("image_id", arguments: arguments)
            let confirmation = try subscriptionVersionedCanonicalIdentifier(
                "confirm_image_id",
                arguments: arguments
            )
            guard confirmation == imageID else {
                return MCPResult.error(
                    "Deleting a subscription version image is irreversible. Set confirm_image_id to the exact image_id to continue."
                )
            }
            endpoint = "/v2/subscriptionImages/\(try ASCPathSegment.encode(imageID, field: "image_id"))"
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription version image deletion")
        }

        do {
            _ = try await httpClient.delete(endpoint)
            return MCPResult.jsonObject([
                "success": true,
                "image_id": imageID,
                "deleted": true,
                "deletionState": "confirmed",
                "outcomeUnknown": false,
                "retrySafe": false
            ])
        } catch {
            return subscriptionVersionedDeletionFailure(
                resourceName: "subscription version image",
                targetField: "image_id",
                targetID: imageID,
                error: error,
                inspectionTool: "subscriptions_get_version_image"
            )
        }
    }

    func createSubscriptionGroupVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let groupID: String
        do {
            let arguments = try subscriptionVersionedArguments(params.arguments, allowed: ["group_id"])
            groupID = try subscriptionVersionedCanonicalIdentifier("group_id", arguments: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription group version creation")
        }

        let body: Data
        do {
            _ = try ASCPathSegment.encode(groupID, field: "group_id")
            body = try JSONEncoder().encode(CreateSubscriptionGroupVersionRequest(groupID: groupID))
        } catch {
            return MCPResult.error(error, prefix: "Failed to create subscription group version")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/subscriptionGroupVersions", body: body)
        } catch {
            return MCPResult.error(
                "Failed to create subscription group version: \(error.localizedDescription)",
                details: ASCNonIdempotentWriteRecovery.failureDetails(
                    for: error,
                    phase: .request,
                    operation: "subscriptions_create_group_version",
                    identifiers: ["group_id": .string(groupID)],
                    listTool: "subscriptions_list_group_versions",
                    listArguments: ["group_id": .string(groupID), "limit": .int(200)],
                    getTool: "subscriptions_get_group_version",
                    getIDArgument: "version_id",
                    listResultIDPath: "versions[].id",
                    matchingFields: ["group_id"]
                )
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Subscription group version create"
            )
            let response = try JSONDecoder().decode(
                ASCSubscriptionGroupVersionResponse.self,
                from: receipt.data
            )
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: "/v1/subscriptionGroupVersions/\(try ASCPathSegment.encode(response.data.id))",
                context: "Apple subscription group version create response"
            )
            try validateSubscriptionGroupVersionResource(
                response.data,
                expectedGroupID: groupID,
                context: "Apple subscription group version create response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "version": formatSubscriptionGroupVersion(response.data)
            ])
        } catch {
            return MCPResult.error(
                "Failed to create subscription group version: \(error.localizedDescription)",
                details: ASCNonIdempotentWriteRecovery.failureDetails(
                    for: error,
                    phase: .acceptedResponse,
                    operation: "subscriptions_create_group_version",
                    identifiers: ["group_id": .string(groupID)],
                    listTool: "subscriptions_list_group_versions",
                    listArguments: ["group_id": .string(groupID), "limit": .int(200)],
                    getTool: "subscriptions_get_group_version",
                    getIDArgument: "version_id",
                    listResultIDPath: "versions[].id",
                    matchingFields: ["group_id"]
                )
            )
        }
    }

    func getSubscriptionGroupVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let versionID: String
        do {
            let arguments = try subscriptionVersionedArguments(params.arguments, allowed: ["version_id"])
            versionID = try subscriptionVersionedCanonicalIdentifier("version_id", arguments: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription group version lookup")
        }

        do {
            let endpoint = "/v1/subscriptionGroupVersions/\(try ASCPathSegment.encode(versionID, field: "version_id"))"
            let data = try await httpClient.get(endpoint)
            let response = try JSONDecoder().decode(ASCSubscriptionGroupVersionResponse.self, from: data)
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: endpoint,
                context: "Apple subscription group version get response"
            )
            try validateSubscriptionGroupVersionResource(
                response.data,
                expectedID: versionID,
                context: "Apple subscription group version get response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "version": formatSubscriptionGroupVersion(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get subscription group version")
        }
    }

    func listSubscriptionGroupVersions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments: [String: Value]
        let groupID: String
        do {
            arguments = try subscriptionVersionedArguments(
                params.arguments,
                allowed: ["group_id", "filter_state", "limit", "next_url"]
            )
            groupID = try subscriptionVersionedCanonicalIdentifier("group_id", arguments: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription group versions list")
        }

        do {
            let endpoint = "/v1/subscriptionGroups/\(try ASCPathSegment.encode(groupID, field: "group_id"))/versions"
            var query = ["limit": String(try subscriptionVersionedLimit(arguments["limit"]))]
            if let states = try subscriptionCatalogQueryValue(
                arguments["filter_state"],
                field: "filter_state",
                allowedValues: Set(Self.subscriptionVersionStates)
            ) {
                query["filter[state]"] = states
            }

            let response: ASCSubscriptionGroupVersionsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: subscriptionCommercePaginationScope(path: endpoint, query: query),
                    as: ASCSubscriptionGroupVersionsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCSubscriptionGroupVersionsResponse.self
                )
            }
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: endpoint,
                context: "Apple subscription group versions list response"
            )
            try validateSubscriptionGroupVersionCollection(
                response.data,
                expectedGroupID: groupID,
                context: "Apple subscription group versions list response"
            )
            try validateSubscriptionPagingInformation(
                response.meta,
                resourceCount: response.data.count,
                nextLink: response.links.next,
                validatesContinuation: true,
                context: "Apple subscription group versions list response"
            )

            var result: [String: Any] = [
                "success": true,
                "versions": response.data.map(formatSubscriptionGroupVersion),
                "count": response.data.count,
                "total": response.meta?.paging?.total.jsonSafe
            ]
            if let nextURL = response.links.next {
                result["next_url"] = nextURL
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list subscription group versions")
        }
    }

    func listSubscriptionGroupVersionLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments: [String: Value]
        let versionID: String
        do {
            arguments = try subscriptionVersionedArguments(
                params.arguments,
                allowed: ["version_id", "limit", "next_url"]
            )
            versionID = try subscriptionVersionedCanonicalIdentifier("version_id", arguments: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription group version localizations list")
        }

        do {
            let endpoint = "/v1/subscriptionGroupVersions/\(try ASCPathSegment.encode(versionID, field: "version_id"))/localizations"
            let query = ["limit": String(try subscriptionVersionedLimit(arguments["limit"]))]
            let response: ASCSubscriptionGroupVersionLocalizationsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: subscriptionCommercePaginationScope(path: endpoint, query: query),
                    as: ASCSubscriptionGroupVersionLocalizationsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCSubscriptionGroupVersionLocalizationsResponse.self
                )
            }
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: endpoint,
                context: "Apple subscription group version localizations list response"
            )
            try validateSubscriptionGroupVersionLocalizationCollection(
                response.data,
                expectedVersionID: versionID,
                context: "Apple subscription group version localizations list response"
            )
            try validateSubscriptionPagingInformation(
                response.meta,
                resourceCount: response.data.count,
                nextLink: response.links.next,
                validatesContinuation: true,
                context: "Apple subscription group version localizations list response"
            )

            var result: [String: Any] = [
                "success": true,
                "localizations": response.data.map(formatSubscriptionGroupVersionLocalization),
                "count": response.data.count,
                "total": response.meta?.paging?.total.jsonSafe
            ]
            if let nextURL = response.links.next {
                result["next_url"] = nextURL
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list subscription group version localizations")
        }
    }

    func createSubscriptionGroupVersionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments: [String: Value]
        let versionID: String
        let locale: String
        let name: String
        do {
            arguments = try subscriptionVersionedArguments(
                params.arguments,
                allowed: ["version_id", "locale", "name", "custom_app_name"]
            )
            versionID = try subscriptionVersionedCanonicalIdentifier("version_id", arguments: arguments)
            guard let localeValue = arguments["locale"]?.stringValue,
                  let nameValue = arguments["name"]?.stringValue else {
                throw ASCError.parsing("Required parameters: version_id, locale, name")
            }
            try requireNonEmptySubscriptionVersionedString(localeValue, field: "locale")
            try requireNonEmptySubscriptionVersionedString(nameValue, field: "name")
            locale = localeValue
            name = nameValue
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription group version localization creation")
        }
        let validationErrors = subscriptionVersionedMetadataValidationErrors(
            arguments,
            locale: locale
        )
        guard validationErrors.isEmpty else {
            return ASCMetadataValidator.errorResult(validationErrors)
        }

        let body: Data
        var identifiers: [String: Value] = [
            "version_id": .string(versionID),
            "locale": .string(locale),
            "name": .string(name)
        ]
        if let customAppName = arguments["custom_app_name"] {
            identifiers["custom_app_name"] = customAppName
        }

        do {
            _ = try ASCPathSegment.encode(versionID, field: "version_id")
            try requireNonEmptySubscriptionVersionedString(locale, field: "locale")
            try requireNonEmptySubscriptionVersionedString(name, field: "name")
            let request = CreateSubscriptionGroupVersionLocalizationRequest(
                versionID: versionID,
                locale: locale,
                name: name,
                customAppName: try subscriptionVersionedNullableString("custom_app_name", arguments: arguments)
            )
            body = try JSONEncoder().encode(request)
        } catch {
            return MCPResult.error(error, prefix: "Failed to create subscription group version localization")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v2/subscriptionGroupLocalizations", body: body)
        } catch {
            return MCPResult.error(
                "Failed to create subscription group version localization: \(error.localizedDescription)",
                details: ASCNonIdempotentWriteRecovery.failureDetails(
                    for: error,
                    phase: .request,
                    operation: "subscriptions_create_group_version_localization",
                    identifiers: identifiers,
                    listTool: "subscriptions_list_group_version_localizations",
                    listArguments: ["version_id": .string(versionID), "limit": .int(200)],
                    getTool: "subscriptions_get_group_version_localization",
                    getIDArgument: "localization_id",
                    listResultIDPath: "localizations[].id",
                    matchingFields: ["version_id", "locale", "name", "custom_app_name"]
                )
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Subscription group version localization create"
            )
            let response = try JSONDecoder().decode(
                ASCSubscriptionGroupVersionLocalizationResponse.self,
                from: receipt.data
            )
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: "/v2/subscriptionGroupLocalizations/\(try ASCPathSegment.encode(response.data.id))",
                context: "Apple subscription group version localization create response"
            )
            try validateSubscriptionGroupVersionLocalizationResource(
                response.data,
                expectedVersionID: versionID,
                context: "Apple subscription group version localization create response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "localization": formatSubscriptionGroupVersionLocalization(response.data)
            ])
        } catch {
            return MCPResult.error(
                "Failed to create subscription group version localization: \(error.localizedDescription)",
                details: ASCNonIdempotentWriteRecovery.failureDetails(
                    for: error,
                    phase: .acceptedResponse,
                    operation: "subscriptions_create_group_version_localization",
                    identifiers: identifiers,
                    listTool: "subscriptions_list_group_version_localizations",
                    listArguments: ["version_id": .string(versionID), "limit": .int(200)],
                    getTool: "subscriptions_get_group_version_localization",
                    getIDArgument: "localization_id",
                    listResultIDPath: "localizations[].id",
                    matchingFields: ["version_id", "locale", "name", "custom_app_name"]
                )
            )
        }
    }

    func getSubscriptionGroupVersionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let localizationID: String
        do {
            let arguments = try subscriptionVersionedArguments(params.arguments, allowed: ["localization_id"])
            localizationID = try subscriptionVersionedCanonicalIdentifier("localization_id", arguments: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription group version localization lookup")
        }

        do {
            let endpoint = "/v2/subscriptionGroupLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))"
            let data = try await httpClient.get(endpoint)
            let response = try JSONDecoder().decode(ASCSubscriptionGroupVersionLocalizationResponse.self, from: data)
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: endpoint,
                context: "Apple subscription group version localization get response"
            )
            try validateSubscriptionGroupVersionLocalizationResource(
                response.data,
                expectedID: localizationID,
                context: "Apple subscription group version localization get response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "localization": formatSubscriptionGroupVersionLocalization(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get subscription group version localization")
        }
    }

    func updateSubscriptionGroupVersionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments: [String: Value]
        let localizationID: String
        do {
            arguments = try subscriptionVersionedArguments(
                params.arguments,
                allowed: ["localization_id", "name", "custom_app_name"]
            )
            localizationID = try subscriptionVersionedCanonicalIdentifier("localization_id", arguments: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription group version localization update")
        }
        guard arguments["name"] != nil || arguments["custom_app_name"] != nil else {
            return MCPResult.error("At least one of name or custom_app_name is required")
        }
        let validationErrors = subscriptionVersionedMetadataValidationErrors(arguments)
        guard validationErrors.isEmpty else {
            return ASCMetadataValidator.errorResult(validationErrors)
        }
        var requestedArguments: [String: Value] = ["localization_id": .string(localizationID)]
        if let name = arguments["name"] {
            requestedArguments["name"] = name
        }
        if let customAppName = arguments["custom_app_name"] {
            requestedArguments["custom_app_name"] = customAppName
        }

        let endpoint: String
        let body: Data
        do {
            endpoint = "/v2/subscriptionGroupLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))"
            let request = UpdateSubscriptionGroupVersionLocalizationRequest(
                localizationID: localizationID,
                name: try subscriptionVersionedNullableString("name", arguments: arguments),
                customAppName: try subscriptionVersionedNullableString("custom_app_name", arguments: arguments)
            )
            body = try JSONEncoder().encode(request)
        } catch {
            return MCPResult.error(error, prefix: "Failed to update subscription group version localization")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(endpoint, body: body)
        } catch {
            return subscriptionMutationRequestFailure(
                operation: "subscriptions_update_group_version_localization",
                action: "subscription group version localization update",
                targetField: "localization_id",
                targetID: localizationID,
                requestedArguments: requestedArguments,
                error: error,
                inspectionTool: "subscriptions_get_group_version_localization"
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 200,
                context: "Subscription group version localization update"
            )
            let response = try JSONDecoder().decode(
                ASCSubscriptionGroupVersionLocalizationResponse.self,
                from: receipt.data
            )
            try validateSubscriptionDocumentSelfLink(
                response.links.`self`,
                expectedPath: endpoint,
                context: "Apple subscription group version localization update response"
            )
            try validateSubscriptionGroupVersionLocalizationResource(
                response.data,
                expectedID: localizationID,
                context: "Apple subscription group version localization update response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "localization": formatSubscriptionGroupVersionLocalization(response.data)
            ])
        } catch {
            return subscriptionCommittedUnverifiedMutationFailure(
                operation: "subscriptions_update_group_version_localization",
                targetField: "localization_id",
                targetID: localizationID,
                requestedArguments: requestedArguments,
                error: error,
                inspectionTool: "subscriptions_get_group_version_localization"
            )
        }
    }

    func deleteSubscriptionGroupVersionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let localizationID: String
        let endpoint: String
        do {
            let arguments = try subscriptionVersionedArguments(
                params.arguments,
                allowed: ["localization_id", "confirm_localization_id"]
            )
            localizationID = try subscriptionVersionedCanonicalIdentifier("localization_id", arguments: arguments)
            let confirmation = try subscriptionVersionedCanonicalIdentifier(
                "confirm_localization_id",
                arguments: arguments
            )
            guard confirmation == localizationID else {
                return MCPResult.error(
                    "Deleting a subscription group version localization is irreversible. Set confirm_localization_id to the exact localization_id to continue."
                )
            }
            endpoint = "/v2/subscriptionGroupLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))"
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate subscription group version localization deletion")
        }

        do {
            _ = try await httpClient.delete(endpoint)
            return MCPResult.jsonObject([
                "success": true,
                "localization_id": localizationID,
                "deleted": true,
                "deletionState": "confirmed",
                "outcomeUnknown": false,
                "retrySafe": false
            ])
        } catch {
            return subscriptionVersionedDeletionFailure(
                resourceName: "subscription group version localization",
                targetField: "localization_id",
                targetID: localizationID,
                error: error,
                inspectionTool: "subscriptions_get_group_version_localization"
            )
        }
    }

    private func subscriptionVersionedArguments(
        _ arguments: [String: Value]?,
        allowed: Set<String>
    ) throws -> [String: Value] {
        let arguments = arguments ?? [:]
        let unsupported = Set(arguments.keys).subtracting(allowed).sorted()
        guard unsupported.isEmpty else {
            throw ASCError.parsing("Unsupported parameter(s): \(unsupported.joined(separator: ", "))")
        }
        return arguments
    }

    private func subscriptionVersionedLimit(_ value: Value?) throws -> Int {
        guard let value else { return 25 }
        guard let limit = value.intValue, (1...200).contains(limit) else {
            throw ASCError.parsing("'limit' must be an integer between 1 and 200")
        }
        return limit
    }

    private func subscriptionVersionedNullableString(
        _ field: String,
        arguments: [String: Value]
    ) throws -> NullableAttributeValue? {
        guard let value = arguments[field] else { return nil }
        if case .null = value {
            return .null
        }
        guard let string = value.stringValue else {
            throw ASCError.parsing("'\(field)' must be a string or null")
        }
        return .string(string)
    }

    private func subscriptionVersionedCanonicalIdentifier(
        _ field: String,
        arguments: [String: Value]
    ) throws -> String {
        guard let identifier = arguments[field]?.stringValue,
              !identifier.isEmpty,
              identifier == identifier.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ASCError.parsing("'\(field)' must be a canonical non-empty resource ID")
        }
        guard try ASCPathSegment.encode(identifier, field: field) == identifier else {
            throw ASCError.parsing("'\(field)' must be a canonical App Store Connect resource ID")
        }
        return identifier
    }

    private func subscriptionVersionedDeletionFailure(
        resourceName: String,
        targetField: String,
        targetID: String,
        error: Error,
        inspectionTool: String
    ) -> CallTool.Result {
        let ascError = error as? ASCError
        let deletionState: String
        let operationCommitState: String
        let outcomeUnknown: Bool
        let operationCommitted: Bool
        let inspectionRequired: Bool
        let message: String

        switch ascError {
        case .deleteCommittedUnverified:
            deletionState = "committed_unverified"
            operationCommitState = "committed_unverified"
            outcomeUnknown = false
            operationCommitted = true
            inspectionRequired = true
            message = "Apple accepted the \(resourceName) delete request, but completion is unverified. Do not retry until the exact target is inspected."
        case .deleteOutcomeUnknown:
            deletionState = "commit_unknown"
            operationCommitState = "unknown"
            outcomeUnknown = true
            operationCommitted = false
            inspectionRequired = true
            message = "The \(resourceName) delete outcome is unknown. Do not retry until the exact target is inspected."
        default:
            deletionState = "rejected"
            operationCommitState = "rejected"
            outcomeUnknown = false
            operationCommitted = false
            inspectionRequired = false
            message = "Failed to delete \(resourceName): \(error.localizedDescription)"
        }

        let cause = ascError?.structuredValue ?? .object([
            "type": .string("unexpected"),
            "message": .string(Redactor.redact(error.localizedDescription))
        ])
        var details: [String: Value] = [
            "deletionState": .string(deletionState),
            "operationCommitState": .string(operationCommitState),
            "outcomeUnknown": .bool(outcomeUnknown),
            "retrySafe": .bool(false),
            "mutationAttempted": .bool(true),
            "targetId": .string(targetID),
            targetField: .string(targetID),
            "cause": cause,
            "inspection": .object([
                "tool": .string(inspectionTool),
                "arguments": .object([targetField: .string(targetID)]),
                "instruction": .string("Inspect this exact resource before another delete attempt.")
            ])
        ]
        if operationCommitted {
            details["operationCommitted"] = .bool(true)
        }
        if inspectionRequired {
            details["inspectionRequired"] = .bool(true)
        }
        var root: [String: Value] = [
            "success": .bool(false),
            "error": .string(Redactor.redact(message)),
            "details": .object(details),
            "operationCommitState": .string(operationCommitState),
            "outcomeUnknown": .bool(outcomeUnknown),
            "retrySafe": .bool(false)
        ]
        if operationCommitted {
            root["operationCommitted"] = .bool(true)
        }
        if inspectionRequired {
            root["inspectionRequired"] = .bool(true)
        }
        return MCPResult.json(
            .object(root),
            text: "Error: \(Redactor.redact(message))",
            isError: true
        )
    }

    private func requireNonEmptySubscriptionVersionedString(_ value: String, field: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == value else {
            throw ASCError.parsing("'\(field)' must be non-empty and contain no surrounding whitespace")
        }
    }

    private func subscriptionVersionedMetadataValidationErrors(
        _ arguments: [String: Value],
        locale: String? = nil
    ) -> [ASCMetadataValidator.FieldError] {
        var errors = locale.map { ASCMetadataValidator.validateLocale($0) } ?? []
        var textFields: [String: String] = [:]
        for field in ["name", "description", "custom_app_name"] {
            if let value = arguments[field]?.stringValue {
                textFields[field] = value
            }
        }
        errors += ASCMetadataValidator.validateTextFields(textFields)
        for field in ["name"] {
            guard let value = textFields[field] else { continue }
            if value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
            }) {
                errors.append(.init(field: field, message: "Control and newline characters are not allowed"))
            }
            if value.range(
                of: #"<\s*/?\s*[A-Za-z][^<>]*>"#,
                options: .regularExpression
            ) != nil {
                errors.append(.init(field: field, message: "Markup tags are not allowed"))
            }
        }
        return errors
    }

    private func validateSubscriptionVersionResource(
        _ version: ASCSubscriptionVersion,
        expectedID: String? = nil,
        expectedSubscriptionID: String? = nil,
        context: String
    ) throws {
        try validateSubscriptionResourceIdentity(
            type: version.type,
            id: version.id,
            expectedType: "subscriptionVersions",
            expectedID: expectedID,
            context: context
        )
        if let subscription = version.relationships?.subscription?.data {
            try validateSubscriptionRelationshipIdentity(
                subscription,
                expectedType: "subscriptions",
                expectedID: expectedSubscriptionID,
                context: "\(context) subscription relationship"
            )
        }
        if let image = version.relationships?.image?.data {
            try validateSubscriptionRelationshipIdentity(
                image,
                expectedType: "subscriptionImages",
                context: "\(context) image relationship"
            )
        }
        try validateSubscriptionPagedRelationship(
            version.relationships?.images,
            expectedType: "subscriptionImages",
            context: "\(context) images relationship"
        )
        try validateSubscriptionPagedRelationship(
            version.relationships?.localizations,
            expectedType: "subscriptionLocalizations",
            context: "\(context) localizations relationship"
        )
    }

    private func validateSubscriptionVersionCollection(
        _ versions: [ASCSubscriptionVersion],
        expectedSubscriptionID: String,
        context: String
    ) throws {
        try validateSubscriptionResourceCollection(
            versions.map { (type: $0.type, id: $0.id) },
            expectedType: "subscriptionVersions",
            context: context
        )
        for version in versions {
            try validateSubscriptionVersionResource(
                version,
                expectedSubscriptionID: expectedSubscriptionID,
                context: "\(context) resource '\(version.id)'"
            )
        }
    }

    private func validateSubscriptionVersionLocalizationResource(
        _ localization: ASCSubscriptionVersionLocalization,
        expectedID: String? = nil,
        expectedVersionID: String? = nil,
        context: String
    ) throws {
        try validateSubscriptionResourceIdentity(
            type: localization.type,
            id: localization.id,
            expectedType: "subscriptionLocalizations",
            expectedID: expectedID,
            context: context
        )
        if let version = localization.relationships?.version?.data {
            try validateSubscriptionRelationshipIdentity(
                version,
                expectedType: "subscriptionVersions",
                expectedID: expectedVersionID,
                context: "\(context) version relationship"
            )
        }
    }

    private func validateSubscriptionVersionLocalizationCollection(
        _ localizations: [ASCSubscriptionVersionLocalization],
        expectedVersionID: String,
        context: String
    ) throws {
        try validateSubscriptionResourceCollection(
            localizations.map { (type: $0.type, id: $0.id) },
            expectedType: "subscriptionLocalizations",
            context: context
        )
        for localization in localizations {
            try validateSubscriptionVersionLocalizationResource(
                localization,
                expectedVersionID: expectedVersionID,
                context: "\(context) resource '\(localization.id)'"
            )
        }
    }

    private func validateSubscriptionVersionImageResource(
        _ image: ASCSubscriptionVersionImage,
        expectedID: String? = nil,
        context: String
    ) throws {
        try validateSubscriptionResourceIdentity(
            type: image.type,
            id: image.id,
            expectedType: "subscriptionImages",
            expectedID: expectedID,
            context: context
        )
    }

    private func validateSubscriptionVersionImageCollection(
        _ images: [ASCSubscriptionVersionImage],
        context: String
    ) throws {
        try validateSubscriptionResourceCollection(
            images.map { (type: $0.type, id: $0.id) },
            expectedType: "subscriptionImages",
            context: context
        )
    }

    private func validateSubscriptionGroupVersionResource(
        _ version: ASCSubscriptionGroupVersion,
        expectedID: String? = nil,
        expectedGroupID: String? = nil,
        context: String
    ) throws {
        try validateSubscriptionResourceIdentity(
            type: version.type,
            id: version.id,
            expectedType: "subscriptionGroupVersions",
            expectedID: expectedID,
            context: context
        )
        if let group = version.relationships?.subscriptionGroup?.data {
            try validateSubscriptionRelationshipIdentity(
                group,
                expectedType: "subscriptionGroups",
                expectedID: expectedGroupID,
                context: "\(context) subscription group relationship"
            )
        }
        try validateSubscriptionPagedRelationship(
            version.relationships?.localizations,
            expectedType: "subscriptionGroupLocalizations",
            context: "\(context) localizations relationship"
        )
    }

    private func validateSubscriptionGroupVersionCollection(
        _ versions: [ASCSubscriptionGroupVersion],
        expectedGroupID: String,
        context: String
    ) throws {
        try validateSubscriptionResourceCollection(
            versions.map { (type: $0.type, id: $0.id) },
            expectedType: "subscriptionGroupVersions",
            context: context
        )
        for version in versions {
            try validateSubscriptionGroupVersionResource(
                version,
                expectedGroupID: expectedGroupID,
                context: "\(context) resource '\(version.id)'"
            )
        }
    }

    private func validateSubscriptionGroupVersionLocalizationResource(
        _ localization: ASCSubscriptionGroupVersionLocalization,
        expectedID: String? = nil,
        expectedVersionID: String? = nil,
        context: String
    ) throws {
        try validateSubscriptionResourceIdentity(
            type: localization.type,
            id: localization.id,
            expectedType: "subscriptionGroupLocalizations",
            expectedID: expectedID,
            context: context
        )
        if let version = localization.relationships?.version?.data {
            try validateSubscriptionRelationshipIdentity(
                version,
                expectedType: "subscriptionGroupVersions",
                expectedID: expectedVersionID,
                context: "\(context) version relationship"
            )
        }
    }

    private func validateSubscriptionGroupVersionLocalizationCollection(
        _ localizations: [ASCSubscriptionGroupVersionLocalization],
        expectedVersionID: String,
        context: String
    ) throws {
        try validateSubscriptionResourceCollection(
            localizations.map { (type: $0.type, id: $0.id) },
            expectedType: "subscriptionGroupLocalizations",
            context: context
        )
        for localization in localizations {
            try validateSubscriptionGroupVersionLocalizationResource(
                localization,
                expectedVersionID: expectedVersionID,
                context: "\(context) resource '\(localization.id)'"
            )
        }
    }

    private func formatSubscriptionVersion(_ version: ASCSubscriptionVersion) -> [String: Any] {
        let imageIDs = version.relationships?.images?.data?.map(\.id)
        let localizationIDs = version.relationships?.localizations?.data?.map(\.id)
        var result: [String: Any] = [
            "id": version.id,
            "type": version.type,
            "version": version.attributes?.version.jsonSafe,
            "state": version.attributes?.state.jsonSafe,
            "subscription_id": version.relationships?.subscription?.data?.id.jsonSafe,
            "image_id": version.relationships?.image?.data?.id.jsonSafe,
            "image_ids": imageIDs.jsonSafe,
            "localization_ids": localizationIDs.jsonSafe
        ]
        if let images = version.relationships?.images {
            result["images_page"] = formatSubscriptionVersionedRelationshipPage(images)
        }
        if let localizations = version.relationships?.localizations {
            result["localizations_page"] = formatSubscriptionVersionedRelationshipPage(localizations)
        }
        return result
    }

    private func formatSubscriptionVersionLocalization(
        _ localization: ASCSubscriptionVersionLocalization
    ) -> [String: Any] {
        return [
            "id": localization.id,
            "type": localization.type,
            "locale": localization.attributes?.locale.jsonSafe,
            "name": localization.attributes?.name.jsonSafe,
            "description": localization.attributes?.description.jsonSafe,
            "version_id": localization.relationships?.version?.data?.id.jsonSafe
        ]
    }

    private func formatSubscriptionVersionImage(_ image: ASCSubscriptionVersionImage) -> [String: Any] {
        var result: [String: Any] = [
            "id": image.id,
            "type": image.type,
            "file_name": image.attributes?.fileName.jsonSafe,
            "file_size": image.attributes?.fileSize.jsonSafe,
            "delivery_state": image.attributes?.assetDeliveryState?.state.jsonSafe
        ]
        if let asset = image.attributes?.imageAsset {
            result["image_asset"] = [
                "template_url": asset.templateUrl.jsonSafe,
                "width": asset.width.jsonSafe,
                "height": asset.height.jsonSafe
            ] as [String: Any]
        }
        if let errors = image.attributes?.assetDeliveryState?.errors {
            result["errors"] = errors.map {
                ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe] as [String: Any]
            }
        }
        if let warnings = image.attributes?.assetDeliveryState?.warnings {
            result["warnings"] = warnings.map {
                ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe] as [String: Any]
            }
        }
        return result
    }

    private func formatSubscriptionGroupVersion(_ version: ASCSubscriptionGroupVersion) -> [String: Any] {
        let localizationIDs = version.relationships?.localizations?.data?.map(\.id)
        var result: [String: Any] = [
            "id": version.id,
            "type": version.type,
            "version": version.attributes?.version.jsonSafe,
            "state": version.attributes?.state.jsonSafe,
            "group_id": version.relationships?.subscriptionGroup?.data?.id.jsonSafe,
            "localization_ids": localizationIDs.jsonSafe
        ]
        if let localizations = version.relationships?.localizations {
            result["localizations_page"] = formatSubscriptionVersionedRelationshipPage(localizations)
        }
        return result
    }

    private func formatSubscriptionVersionedRelationshipPage(
        _ relationship: ASCPricingPagedRelationship
    ) -> [String: Any] {
        let ids = relationship.data?.map(\.id)
        let count = ids?.count
        let total = relationship.meta?.paging?.total
        let nextCursor = relationship.meta?.paging?.nextCursor
        let truncated = count.flatMap { count in
            nextCursor != nil ? true : total.map { $0 > count }
        }
        return [
            "ids": ids.jsonSafe,
            "count": count.jsonSafe,
            "total": total.jsonSafe,
            "limit": relationship.meta?.paging?.limit.jsonSafe,
            "next_cursor": nextCursor.jsonSafe,
            "truncated": truncated.jsonSafe,
            "completeness_known": count != nil && (total != nil || nextCursor != nil)
        ]
    }

    private func formatSubscriptionGroupVersionLocalization(
        _ localization: ASCSubscriptionGroupVersionLocalization
    ) -> [String: Any] {
        [
            "id": localization.id,
            "type": localization.type,
            "locale": localization.attributes?.locale.jsonSafe,
            "name": localization.attributes?.name.jsonSafe,
            "custom_app_name": localization.attributes?.customAppName.jsonSafe,
            "version_id": localization.relationships?.version?.data?.id.jsonSafe
        ]
    }
}
