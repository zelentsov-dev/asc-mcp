import Foundation
import MCP

extension InAppPurchasesWorker {
    func createIAPVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapID = arguments["iap_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'iap_id' is missing")
        }

        let body: Data
        do {
            try validateIAPVersionedInputIdentifier(
                iapID,
                type: "inAppPurchases",
                field: "iap_id"
            )
            body = try JSONEncoder().encode(CreateIAPVersionRequest(iapID: iapID))
        } catch {
            return MCPResult.error(error, prefix: "Failed to create IAP version")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/inAppPurchaseVersions", body: body)
        } catch {
            return iapVersionedNonIdempotentFailure(
                message: "Failed to create IAP version: \(error.localizedDescription)",
                error: error,
                phase: .request,
                operation: "iap_create_version",
                identifiers: ["iap_id": .string(iapID)],
                listTool: "iap_list_versions",
                listArguments: ["iap_id": .string(iapID), "limit": .int(200)],
                getTool: "iap_get_version",
                getIDArgument: "version_id",
                listResultIDPath: "versions[].id",
                matchingFields: ["iap_id"]
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "IAP version creation"
            )
            let response = try JSONDecoder().decode(ASCIAPVersionResponse.self, from: receipt.data)
            try validateIAPVersion(
                response.data,
                expectedIAPID: iapID,
                context: "IAP version create response"
            )
            try validateIAPVersionedDocumentLinks(
                response.links,
                expectedPath: "/v1/inAppPurchaseVersions/\(try ASCPathSegment.encode(response.data.id))",
                context: "IAP version create response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "version": formatIAPVersion(response.data)
            ])
        } catch {
            return iapVersionedNonIdempotentFailure(
                message: "Failed to create IAP version: \(error.localizedDescription)",
                error: error,
                phase: .acceptedResponse,
                operation: "iap_create_version",
                identifiers: ["iap_id": .string(iapID)],
                listTool: "iap_list_versions",
                listArguments: ["iap_id": .string(iapID), "limit": .int(200)],
                getTool: "iap_get_version",
                getIDArgument: "version_id",
                listResultIDPath: "versions[].id",
                matchingFields: ["iap_id"]
            )
        }
    }

    func getIAPVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionID = arguments["version_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'version_id' is missing")
        }

        do {
            try validateIAPVersionedInputIdentifier(
                versionID,
                type: "inAppPurchaseVersions",
                field: "version_id"
            )
            let endpoint = "/v1/inAppPurchaseVersions/\(try ASCPathSegment.encode(versionID, field: "version_id"))"
            let data = try await httpClient.get(endpoint)
            let response = try JSONDecoder().decode(ASCIAPVersionResponse.self, from: data)
            try validateIAPVersion(
                response.data,
                expectedID: versionID,
                context: "IAP version get response"
            )
            try validateIAPVersionedDocumentLinks(
                response.links,
                expectedPath: endpoint,
                context: "IAP version get response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "version": formatIAPVersion(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get IAP version")
        }
    }

    func listIAPVersions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let iapID = arguments["iap_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'iap_id' is missing")
        }

        do {
            try validateIAPVersionedInputIdentifier(
                iapID,
                type: "inAppPurchases",
                field: "iap_id"
            )
            let endpoint = "/v2/inAppPurchases/\(try ASCPathSegment.encode(iapID, field: "iap_id"))/versions"
            var query = ["limit": String(try iapVersionedLimit(arguments["limit"], maximum: 200))]
            if let states = try iapCatalogQueryValue(
                arguments["filter_state"],
                field: "filter_state",
                allowedValues: Set(Self.iapVersionStates)
            ) {
                query["filter[state]"] = states
            }

            let response: ASCIAPVersionsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: iapCommercePaginationScope(path: endpoint, query: query),
                    as: ASCIAPVersionsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCIAPVersionsResponse.self
                )
            }

            try validateIAPVersions(
                response.data,
                expectedIAPID: iapID,
                context: "IAP version list response"
            )
            try validateIAPVersionedPagingMetadata(
                response.meta,
                pageCount: response.data.count,
                hasNextLink: response.links.next != nil,
                context: "IAP version list response"
            )
            try validateIAPVersionedDocumentLinks(
                response.links,
                expectedPath: endpoint,
                context: "IAP version list response"
            )

            var result: [String: Any] = [
                "success": true,
                "versions": response.data.map(formatIAPVersion),
                "count": response.data.count,
                "total": response.meta?.paging.total.jsonSafe
            ]
            if let nextURL = response.links.next {
                result["next_url"] = nextURL
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list IAP versions")
        }
    }

    func listIAPVersionLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionID = arguments["version_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'version_id' is missing")
        }

        do {
            try validateIAPVersionedInputIdentifier(
                versionID,
                type: "inAppPurchaseVersions",
                field: "version_id"
            )
            let endpoint = "/v1/inAppPurchaseVersions/\(try ASCPathSegment.encode(versionID, field: "version_id"))/localizations"
            let query = ["limit": String(try iapVersionedLimit(arguments["limit"], maximum: 200))]
            let response: ASCIAPVersionLocalizationsResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: iapCommercePaginationScope(path: endpoint, query: query),
                    as: ASCIAPVersionLocalizationsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCIAPVersionLocalizationsResponse.self
                )
            }

            try validateIAPVersionLocalizations(
                response.data,
                expectedVersionID: versionID,
                context: "IAP version localization list response"
            )
            try validateIAPVersionedPagingMetadata(
                response.meta,
                pageCount: response.data.count,
                hasNextLink: response.links.next != nil,
                context: "IAP version localization list response"
            )
            try validateIAPVersionedDocumentLinks(
                response.links,
                expectedPath: endpoint,
                context: "IAP version localization list response"
            )

            var result: [String: Any] = [
                "success": true,
                "localizations": response.data.map(formatIAPVersionLocalization),
                "count": response.data.count,
                "total": response.meta?.paging.total.jsonSafe
            ]
            if let nextURL = response.links.next {
                result["next_url"] = nextURL
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list IAP version localizations")
        }
    }

    func createIAPVersionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionID = arguments["version_id"]?.stringValue,
              let locale = arguments["locale"]?.stringValue,
              let name = arguments["name"]?.stringValue else {
            return MCPResult.error("Required parameters: version_id, locale, name")
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

        let validationErrors = validateIAPLocalizationArguments(arguments, locale: locale)
        if !validationErrors.isEmpty {
            return ASCMetadataValidator.errorResult(validationErrors)
        }

        do {
            try validateIAPVersionedInputIdentifier(
                versionID,
                type: "inAppPurchaseVersions",
                field: "version_id"
            )
            try requireNonEmptyIAPVersionedString(locale, field: "locale")
            try validateIAPVersionedLocalizationName(name)
            let description = try iapVersionedNullableString("description", arguments: arguments)
            let request = CreateIAPVersionLocalizationRequest(
                versionID: versionID,
                locale: locale,
                name: name,
                description: description
            )
            body = try JSONEncoder().encode(request)
        } catch {
            return MCPResult.error(error, prefix: "Failed to create IAP version localization")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v2/inAppPurchaseLocalizations", body: body)
        } catch {
            return iapVersionedNonIdempotentFailure(
                message: "Failed to create IAP version localization: \(error.localizedDescription)",
                error: error,
                phase: .request,
                operation: "iap_create_version_localization",
                identifiers: identifiers,
                listTool: "iap_list_version_localizations",
                listArguments: ["version_id": .string(versionID), "limit": .int(200)],
                getTool: "iap_get_version_localization",
                getIDArgument: "localization_id",
                listResultIDPath: "localizations[].id",
                matchingFields: ["version_id", "locale", "name", "description"]
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "IAP version localization creation"
            )
            let response = try JSONDecoder().decode(ASCIAPVersionLocalizationResponse.self, from: receipt.data)
            try validateIAPVersionLocalization(
                response.data,
                expectedVersionID: versionID,
                context: "IAP version localization create response"
            )
            try validateIAPVersionedDocumentLinks(
                response.links,
                expectedPath: "/v2/inAppPurchaseLocalizations/\(try ASCPathSegment.encode(response.data.id))",
                context: "IAP version localization create response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "localization": formatIAPVersionLocalization(response.data)
            ])
        } catch {
            return iapVersionedNonIdempotentFailure(
                message: "Failed to create IAP version localization: \(error.localizedDescription)",
                error: error,
                phase: .acceptedResponse,
                operation: "iap_create_version_localization",
                identifiers: identifiers,
                listTool: "iap_list_version_localizations",
                listArguments: ["version_id": .string(versionID), "limit": .int(200)],
                getTool: "iap_get_version_localization",
                getIDArgument: "localization_id",
                listResultIDPath: "localizations[].id",
                matchingFields: ["version_id", "locale", "name", "description"]
            )
        }
    }

    func getIAPVersionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let localizationID = arguments["localization_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'localization_id' is missing")
        }

        do {
            try validateIAPVersionedInputIdentifier(
                localizationID,
                type: "inAppPurchaseLocalizations",
                field: "localization_id"
            )
            let endpoint = "/v2/inAppPurchaseLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))"
            let data = try await httpClient.get(endpoint)
            let response = try JSONDecoder().decode(ASCIAPVersionLocalizationResponse.self, from: data)
            try validateIAPVersionLocalization(
                response.data,
                expectedID: localizationID,
                context: "IAP version localization get response"
            )
            try validateIAPVersionedDocumentLinks(
                response.links,
                expectedPath: endpoint,
                context: "IAP version localization get response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "localization": formatIAPVersionLocalization(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get IAP version localization")
        }
    }

    func updateIAPVersionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let localizationID = arguments["localization_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'localization_id' is missing")
        }
        guard arguments["name"] != nil || arguments["description"] != nil else {
            return MCPResult.error("At least one of name or description is required")
        }
        let validationErrors = validateIAPLocalizationArguments(arguments)
        if !validationErrors.isEmpty {
            return ASCMetadataValidator.errorResult(validationErrors)
        }
        var mutationIdentifiers: [String: Value] = [
            "localization_id": .string(localizationID)
        ]
        if let name = arguments["name"] {
            mutationIdentifiers["name"] = name
        }
        if let description = arguments["description"] {
            mutationIdentifiers["description"] = description
        }

        let endpoint: String
        let request: UpdateIAPVersionLocalizationRequest
        do {
            try validateIAPVersionedInputIdentifier(
                localizationID,
                type: "inAppPurchaseLocalizations",
                field: "localization_id"
            )
            if let name = arguments["name"]?.stringValue {
                try validateIAPVersionedLocalizationName(name)
            }
            endpoint = "/v2/inAppPurchaseLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))"
            request = UpdateIAPVersionLocalizationRequest(
                localizationID: localizationID,
                name: try iapVersionedNullableString("name", arguments: arguments),
                description: try iapVersionedNullableString("description", arguments: arguments)
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to update IAP version localization")
        }

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(request)
        } catch {
            return MCPResult.error(error, prefix: "Failed to update IAP version localization")
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(endpoint, body: requestData)
        } catch {
            return iapVersionedMutationRequestFailure(
                action: "update IAP version localization",
                error: error,
                identifiers: mutationIdentifiers,
                inspectionTool: "iap_get_version_localization",
                inspectionArguments: ["localization_id": .string(localizationID)]
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 200,
                context: "IAP version localization update"
            )
            let response = try JSONDecoder().decode(ASCIAPVersionLocalizationResponse.self, from: receipt.data)
            try validateIAPVersionLocalization(
                response.data,
                expectedID: localizationID,
                context: "IAP version localization update response"
            )
            try validateIAPVersionedDocumentLinks(
                response.links,
                expectedPath: endpoint,
                context: "IAP version localization update response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "localization": formatIAPVersionLocalization(response.data)
            ])
        } catch {
            return iapVersionedCommittedUnverifiedFailure(
                action: "update IAP version localization",
                error: error,
                identifiers: mutationIdentifiers,
                inspectionTool: "iap_get_version_localization",
                inspectionArguments: ["localization_id": .string(localizationID)]
            )
        }
    }

    func deleteIAPVersionLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters are missing: localization_id, confirm_localization_id")
        }

        let localizationID: String
        do {
            localizationID = try confirmedIAPVersionedDeleteIdentifier(
                arguments: arguments,
                idField: "localization_id",
                confirmationField: "confirm_localization_id",
                type: "inAppPurchaseLocalizations",
                resourceName: "IAP version localization"
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to delete IAP version localization")
        }

        do {
            let endpoint = "/v2/inAppPurchaseLocalizations/\(try ASCPathSegment.encode(localizationID, field: "localization_id"))"
            _ = try await httpClient.delete(endpoint)
            return MCPResult.jsonObject([
                "success": true,
                "deletionState": "confirmed",
                "outcomeUnknown": false,
                "retrySafe": false,
                "localization_id": localizationID,
                "deleted": true
            ])
        } catch {
            return iapVersionedDeletionFailure(
                resourceName: "IAP version localization",
                targetField: "localization_id",
                targetID: localizationID,
                error: error,
                inspectionTool: "iap_get_version_localization",
                inspectionArguments: ["localization_id": .string(localizationID)]
            )
        }
    }

    func getIAPVersionImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionID = arguments["version_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'version_id' is missing")
        }

        do {
            try validateIAPVersionedInputIdentifier(
                versionID,
                type: "inAppPurchaseVersions",
                field: "version_id"
            )
            let endpoint = "/v1/inAppPurchaseVersions/\(try ASCPathSegment.encode(versionID, field: "version_id"))/image"
            let data = try await httpClient.get(endpoint)
            let response = try JSONDecoder().decode(ASCIAPVersionImageResponse.self, from: data)
            try validateIAPVersionImage(
                response.data,
                context: "IAP version image relationship response"
            )
            try validateIAPVersionedDocumentLinks(
                response.links,
                expectedPath: endpoint,
                context: "IAP version image relationship response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "image": formatIAPVersionImage(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get IAP version image")
        }
    }

    func listIAPVersionImages(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionID = arguments["version_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'version_id' is missing")
        }

        do {
            try validateIAPVersionedInputIdentifier(
                versionID,
                type: "inAppPurchaseVersions",
                field: "version_id"
            )
            let endpoint = "/v1/inAppPurchaseVersions/\(try ASCPathSegment.encode(versionID, field: "version_id"))/images"
            let query = ["limit": String(try iapVersionedLimit(arguments["limit"], maximum: 200))]
            let response: ASCIAPVersionImagesResponse
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: iapCommercePaginationScope(path: endpoint, query: query),
                    as: ASCIAPVersionImagesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: query,
                    as: ASCIAPVersionImagesResponse.self
                )
            }

            try validateIAPVersionImages(
                response.data,
                context: "IAP version image list response"
            )
            try validateIAPVersionedPagingMetadata(
                response.meta,
                pageCount: response.data.count,
                hasNextLink: response.links.next != nil,
                context: "IAP version image list response"
            )
            try validateIAPVersionedDocumentLinks(
                response.links,
                expectedPath: endpoint,
                context: "IAP version image list response"
            )

            var result: [String: Any] = [
                "success": true,
                "images": response.data.map(formatIAPVersionImage),
                "count": response.data.count,
                "total": response.meta?.paging.total.jsonSafe
            ]
            if let nextURL = response.links.next {
                result["next_url"] = nextURL
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list IAP version images")
        }
    }

    func uploadIAPVersionImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionID = arguments["version_id"]?.stringValue,
              let filePath = arguments["file_path"]?.stringValue else {
            return MCPResult.error("Required parameters: version_id, file_path")
        }

        do {
            try validateIAPVersionedInputIdentifier(
                versionID,
                type: "inAppPurchaseVersions",
                field: "version_id"
            )
            guard (filePath as NSString).isAbsolutePath else {
                throw ASCError.parsing("'file_path' must be an absolute path")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to upload IAP version image")
        }

        let outcome: UploadTransactionOutcome<ASCIAPVersionImage> = await UploadTransactionRecovery.perform(
            filePath: filePath,
            resourceName: "IAP version image",
            expectedType: "inAppPurchaseImages",
            reservationEndpoint: "/v2/inAppPurchaseImages",
            httpClient: httpClient,
            uploadService: uploadService,
            validateReservedResource: { image, snapshot in
                guard image.attributes?.fileName == snapshot.fileName,
                      image.attributes?.fileSize == snapshot.fileSize else {
                    throw ASCError.parsing(
                        "Apple's IAP version image reservation does not match the immutable file snapshot"
                    )
                }
                guard case .pending(let state) = image.recoveryDeliveryStatus,
                      state == "AWAITING_UPLOAD" else {
                    throw ASCError.parsing(
                        "Apple's IAP version image reservation is not awaiting upload"
                    )
                }
            },
            deliveryPollAttempts: deliveryPollAttempts,
            deliveryPollIntervalNanoseconds: deliveryPollIntervalNanoseconds,
            makeReservationBody: { fileSize, fileName in
                try JSONEncoder().encode(
                    CreateIAPVersionImageRequest(
                        versionID: versionID,
                        fileSize: fileSize,
                        fileName: fileName
                    )
                )
            },
            decodeResource: {
                let response = try JSONDecoder().decode(ASCIAPVersionImageResponse.self, from: $0)
                try validateIAPVersionImage(
                    response.data,
                    context: "IAP version image upload response"
                )
                try validateIAPVersionedDocumentLinks(
                    response.links,
                    expectedPath: "/v2/inAppPurchaseImages/\(try ASCPathSegment.encode(response.data.id))",
                    context: "IAP version image upload response"
                )
                return response.data
            },
            makeCommitBody: { imageID, _ in
                try JSONEncoder().encode(CommitIAPVersionImageRequest(imageID: imageID))
            },
            resourceEndpoint: {
                "/v2/inAppPurchaseImages/\(try ASCPathSegment.encode($0, field: "image_id"))"
            }
        )

        return UploadTransactionRecovery.result(
            for: outcome,
            descriptor: UploadRecoveryDescriptor(
                resourceName: "IAP version image",
                successKey: "image",
                idArgument: "image_id",
                getTool: "iap_get_version_image_resource",
                getIDArgument: "image_id",
                deleteTool: "iap_delete_version_image",
                deleteConfirmationArgument: "confirm_image_id",
                inspectionTool: "iap_list_version_images",
                inspectionArguments: ["version_id": versionID],
                inspectionPageLimit: 200,
                inspectionNextURLArgument: "next_url",
                reservationFingerprintKey: "reservationFingerprint",
                inspectionCandidateFields: ["file_name", "file_size"],
                checksumReceiptKey: "sourceFileChecksumReceipt"
            ),
            format: formatIAPVersionImage
        )
    }

    func getIAPVersionImageResource(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let imageID = arguments["image_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'image_id' is missing")
        }

        do {
            try validateIAPVersionedInputIdentifier(
                imageID,
                type: "inAppPurchaseImages",
                field: "image_id"
            )
            let endpoint = "/v2/inAppPurchaseImages/\(try ASCPathSegment.encode(imageID, field: "image_id"))"
            let data = try await httpClient.get(endpoint)
            let response = try JSONDecoder().decode(ASCIAPVersionImageResponse.self, from: data)
            try validateIAPVersionImage(
                response.data,
                expectedID: imageID,
                context: "IAP version image get response"
            )
            try validateIAPVersionedDocumentLinks(
                response.links,
                expectedPath: endpoint,
                context: "IAP version image get response"
            )
            return MCPResult.jsonObject([
                "success": true,
                "image": formatIAPVersionImage(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get IAP version image resource")
        }
    }

    func deleteIAPVersionImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters are missing: image_id, confirm_image_id")
        }

        let imageID: String
        do {
            imageID = try confirmedIAPVersionedDeleteIdentifier(
                arguments: arguments,
                idField: "image_id",
                confirmationField: "confirm_image_id",
                type: "inAppPurchaseImages",
                resourceName: "IAP version image"
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to delete IAP version image")
        }

        do {
            let endpoint = "/v2/inAppPurchaseImages/\(try ASCPathSegment.encode(imageID, field: "image_id"))"
            _ = try await httpClient.delete(endpoint)
            return MCPResult.jsonObject([
                "success": true,
                "deletionState": "confirmed",
                "outcomeUnknown": false,
                "retrySafe": false,
                "image_id": imageID,
                "deleted": true
            ])
        } catch {
            return iapVersionedDeletionFailure(
                resourceName: "IAP version image",
                targetField: "image_id",
                targetID: imageID,
                error: error,
                inspectionTool: "iap_get_version_image_resource",
                inspectionArguments: ["image_id": .string(imageID)]
            )
        }
    }

    private func iapVersionedLimit(_ value: Value?, maximum: Int) throws -> Int {
        guard let value else { return 25 }
        guard let limit = value.intValue, (1...maximum).contains(limit) else {
            throw ASCError.parsing("'limit' must be an integer between 1 and \(maximum)")
        }
        return limit
    }

    private func iapVersionedNullableString(
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

    private func requireNonEmptyIAPVersionedString(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ASCError.parsing("'\(field)' must not be empty")
        }
    }

    private func validateIAPVersionedLocalizationName(_ name: String) throws {
        try requireNonEmptyIAPVersionedString(name, field: "name")
        guard name.count >= 2 else {
            throw ASCError.parsing("'name' must contain at least 2 characters")
        }
    }

    private func validateIAPVersionedInputIdentifier(
        _ id: String,
        type: String,
        field: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: type,
            id: id,
            expectedType: type,
            expectedID: id,
            context: "requested \(field)"
        )
    }

    private func validateIAPVersion(
        _ version: ASCIAPVersion,
        expectedID: String? = nil,
        expectedIAPID: String? = nil,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: version.type,
            id: version.id,
            expectedType: "inAppPurchaseVersions",
            expectedID: expectedID,
            context: context
        )

        if let expectedIAPID,
           let purchase = version.relationships?.inAppPurchase?.data {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: purchase.type,
                id: purchase.id,
                expectedType: "inAppPurchases",
                expectedID: expectedIAPID,
                context: "\(context) inAppPurchase relationship"
            )
        } else if let purchase = version.relationships?.inAppPurchase?.data {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: purchase.type,
                id: purchase.id,
                expectedType: "inAppPurchases",
                context: "\(context) inAppPurchase relationship"
            )
        }

        if let image = version.relationships?.image?.data {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: image.type,
                id: image.id,
                expectedType: "inAppPurchaseImages",
                context: "\(context) image relationship"
            )
        }
        try validateIAPVersionedRelationshipPage(
            version.relationships?.images,
            expectedType: "inAppPurchaseImages",
            context: "\(context) images relationship"
        )
        try validateIAPVersionedRelationshipPage(
            version.relationships?.localizations,
            expectedType: "inAppPurchaseLocalizations",
            context: "\(context) localizations relationship"
        )
    }

    private func validateIAPVersions(
        _ versions: [ASCIAPVersion],
        expectedIAPID: String,
        context: String
    ) throws {
        var identities = Set<String>()
        for version in versions {
            try validateIAPVersion(
                version,
                expectedIAPID: expectedIAPID,
                context: context
            )
            guard identities.insert("\(version.type):\(version.id)").inserted else {
                throw ASCError.parsing("Apple returned a duplicate resource identity for \(context)")
            }
        }
    }

    private func validateIAPVersionLocalization(
        _ localization: ASCIAPVersionLocalization,
        expectedID: String? = nil,
        expectedVersionID: String? = nil,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: localization.type,
            id: localization.id,
            expectedType: "inAppPurchaseLocalizations",
            expectedID: expectedID,
            context: context
        )

        if let expectedVersionID,
           let version = localization.relationships?.version?.data {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: version.type,
                id: version.id,
                expectedType: "inAppPurchaseVersions",
                expectedID: expectedVersionID,
                context: "\(context) version relationship"
            )
        } else if let version = localization.relationships?.version?.data {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: version.type,
                id: version.id,
                expectedType: "inAppPurchaseVersions",
                context: "\(context) version relationship"
            )
        }
    }

    private func validateIAPVersionLocalizations(
        _ localizations: [ASCIAPVersionLocalization],
        expectedVersionID: String,
        context: String
    ) throws {
        var identities = Set<String>()
        for localization in localizations {
            try validateIAPVersionLocalization(
                localization,
                expectedVersionID: expectedVersionID,
                context: context
            )
            guard identities.insert("\(localization.type):\(localization.id)").inserted else {
                throw ASCError.parsing("Apple returned a duplicate resource identity for \(context)")
            }
        }
    }

    private func validateIAPVersionImage(
        _ image: ASCIAPVersionImage,
        expectedID: String? = nil,
        context: String
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: image.type,
            id: image.id,
            expectedType: "inAppPurchaseImages",
            expectedID: expectedID,
            context: context
        )
    }

    private func validateIAPVersionImages(
        _ images: [ASCIAPVersionImage],
        context: String
    ) throws {
        var identities = Set<String>()
        for image in images {
            try validateIAPVersionImage(image, context: context)
            guard identities.insert("\(image.type):\(image.id)").inserted else {
                throw ASCError.parsing("Apple returned a duplicate resource identity for \(context)")
            }
        }
    }

    private func validateIAPVersionedDocumentLinks(
        _ links: ASCPagedDocumentLinks,
        expectedPath: String,
        context: String
    ) throws {
        let link = links.`self`
        guard link == link.trimmingCharacters(in: .whitespacesAndNewlines),
              !link.isEmpty,
              let components = URLComponents(string: link),
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              components.percentEncodedPath == expectedPath else {
            throw ASCError.parsing("Apple returned an invalid links.self for \(context)")
        }
        if components.scheme != nil {
            guard let scheme = components.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  components.host != nil else {
                throw ASCError.parsing("Apple returned an invalid links.self origin for \(context)")
            }
        }
    }

    private func validateIAPVersionedRelationshipCollection(
        _ resources: [ASCResourceIdentifier]?,
        expectedType: String,
        context: String
    ) throws {
        guard let resources else { return }
        var identities = Set<String>()
        for resource in resources {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: resource.type,
                id: resource.id,
                expectedType: expectedType,
                context: context
            )
            guard identities.insert("\(resource.type):\(resource.id)").inserted else {
                throw ASCError.parsing("Apple returned a duplicate resource identity for \(context)")
            }
        }
    }

    private func validateIAPVersionedRelationshipPage(
        _ relationship: ASCIAPVersionPagedRelationship?,
        expectedType: String,
        context: String
    ) throws {
        guard let relationship else { return }
        let resources = relationship.data ?? []
        try validateIAPVersionedRelationshipCollection(
            resources,
            expectedType: expectedType,
            context: context
        )
        try validateIAPVersionedPagingMetadata(
            relationship.meta,
            pageCount: resources.count,
            hasNextLink: nil,
            context: context
        )
    }

    private func validateIAPVersionedPagingMetadata(
        _ meta: ASCIAPVersionPagingInformation?,
        pageCount: Int,
        hasNextLink: Bool?,
        context: String
    ) throws {
        guard let meta else { return }
        let paging = meta.paging
        let limit = paging.limit
        guard limit > 0 else {
            throw ASCError.parsing("Apple returned a non-positive paging.limit for \(context)")
        }
        guard limit >= pageCount else {
            throw ASCError.parsing("Apple returned paging.limit smaller than the resource count for \(context)")
        }
        if let total = paging.total {
            guard total >= 0 else {
                throw ASCError.parsing("Apple returned a negative paging.total for \(context)")
            }
            guard total >= pageCount else {
                throw ASCError.parsing("Apple returned paging.total smaller than the resource count for \(context)")
            }
        }
        if let nextCursor = paging.nextCursor {
            let trimmedCursor = nextCursor.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCursor.isEmpty, trimmedCursor == nextCursor else {
                throw ASCError.parsing("Apple returned an empty or non-canonical paging.nextCursor for \(context)")
            }
            if let hasNextLink, !hasNextLink {
                throw ASCError.parsing("Apple returned paging.nextCursor without links.next for \(context)")
            }
        }
    }

    private func confirmedIAPVersionedDeleteIdentifier(
        arguments: [String: Value],
        idField: String,
        confirmationField: String,
        type: String,
        resourceName: String
    ) throws -> String {
        guard let id = arguments[idField]?.stringValue,
              let confirmation = arguments[confirmationField]?.stringValue else {
            throw ASCError.parsing("Required parameters are missing: \(idField), \(confirmationField)")
        }
        try validateIAPVersionedInputIdentifier(id, type: type, field: idField)
        try validateIAPVersionedInputIdentifier(
            confirmation,
            type: type,
            field: confirmationField
        )
        guard confirmation == id else {
            throw ASCError.parsing(
                "Deleting \(resourceName) is irreversible. Set \(confirmationField) to the exact \(idField) to continue."
            )
        }
        return id
    }

    private func iapVersionedNonIdempotentFailure(
        message: String,
        error: Error,
        phase: ASCNonIdempotentWriteFailurePhase,
        operation: String,
        identifiers: [String: Value],
        listTool: String,
        listArguments: [String: Value],
        getTool: String,
        getIDArgument: String,
        listResultIDPath: String,
        matchingFields: [String]
    ) -> CallTool.Result {
        let details = ASCNonIdempotentWriteRecovery.failureDetails(
            for: error,
            phase: phase,
            operation: operation,
            identifiers: identifiers,
            listTool: listTool,
            listArguments: listArguments,
            getTool: getTool,
            getIDArgument: getIDArgument,
            listResultIDPath: listResultIDPath,
            matchingFields: matchingFields
        )
        var root: [String: Value] = [
            "success": .bool(false),
            "error": .string(Redactor.redact(message)),
            "details": details
        ]
        if case .object(let object) = details {
            for field in [
                "operationCommitState",
                "operationCommitted",
                "outcomeUnknown",
                "inspectionRequired",
                "retrySafe"
            ] where object[field] != nil {
                root[field] = object[field]
            }
        }
        return MCPResult.json(
            .object(root),
            text: "Error: \(Redactor.redact(message))",
            isError: true
        )
    }

    private func iapVersionedMutationRequestFailure(
        action: String,
        error: Error,
        identifiers: [String: Value],
        inspectionTool: String,
        inspectionArguments: [String: Value]
    ) -> CallTool.Result {
        guard iapVersionedMutationOutcomeIsUnknown(error) else {
            return MCPResult.error(error, prefix: "Failed to \(action)")
        }

        var details = identifiers
        details["cause"] = iapVersionedStructuredError(error)
        details["inspection"] = .object([
            "tool": .string(inspectionTool),
            "arguments": .object(inspectionArguments),
            "instruction": .string("Inspect the exact resource before retrying this mutation.")
        ])
        return MCPResult.json(
            .object([
                "success": .bool(false),
                "error": .string("The \(action) outcome is unknown. Inspect the exact resource before retrying."),
                "details": .object(details),
                "operationCommitState": .string("unknown"),
                "outcomeUnknown": .bool(true),
                "retrySafe": .bool(false)
            ]),
            text: "Error: The \(action) outcome is unknown. Inspect the exact resource before retrying.",
            isError: true
        )
    }

    private func iapVersionedCommittedUnverifiedFailure(
        action: String,
        error: Error,
        identifiers: [String: Value],
        inspectionTool: String,
        inspectionArguments: [String: Value]
    ) -> CallTool.Result {
        var details = identifiers
        details["cause"] = iapVersionedStructuredError(error)
        details["inspection"] = .object([
            "tool": .string(inspectionTool),
            "arguments": .object(inspectionArguments),
            "instruction": .string("Inspect the exact resource before retrying this mutation.")
        ])
        return MCPResult.json(
            .object([
                "success": .bool(false),
                "error": .string("Apple accepted the \(action), but the returned resource identity could not be verified."),
                "details": .object(details),
                "operationCommitState": .string("committed_unverified"),
                "operationCommitted": .bool(true),
                "outcomeUnknown": .bool(false),
                "inspectionRequired": .bool(true),
                "retrySafe": .bool(false)
            ]),
            text: "Error: Apple accepted the \(action), but the returned resource identity could not be verified. Inspect the exact resource before retrying.",
            isError: true
        )
    }

    private func iapVersionedDeletionFailure(
        resourceName: String,
        targetField: String,
        targetID: String,
        error: Error,
        inspectionTool: String,
        inspectionArguments: [String: Value]
    ) -> CallTool.Result {
        let state: String
        let operationCommitState: String
        let outcomeUnknown: Bool
        let operationCommitted: Bool
        let retrySafe: Bool

        if let error = error as? ASCError {
            switch error {
            case .deleteOutcomeUnknown:
                state = "commit_unknown"
                operationCommitState = "unknown"
                outcomeUnknown = true
                operationCommitted = false
                retrySafe = false
            case .deleteCommittedUnverified:
                state = "committed_unverified"
                operationCommitState = "committed_unverified"
                outcomeUnknown = false
                operationCommitted = true
                retrySafe = false
            default:
                state = "rejected"
                operationCommitState = "rejected"
                outcomeUnknown = false
                operationCommitted = false
                retrySafe = true
            }
        } else {
            state = "commit_unknown"
            operationCommitState = "unknown"
            outcomeUnknown = true
            operationCommitted = false
            retrySafe = false
        }

        let message: String
        switch state {
        case "committed_unverified":
            message = "Apple accepted the \(resourceName) delete request, but completion is unverified. Do not retry until the exact target is inspected."
        case "commit_unknown":
            message = "The \(resourceName) delete outcome is unknown. Do not retry until the exact target is inspected."
        default:
            message = "Failed to delete \(resourceName): \(error.localizedDescription)"
        }

        var root: [String: Value] = [
            "success": .bool(false),
            "error": .string(Redactor.redact(message)),
            "operationCommitState": .string(operationCommitState),
            "outcomeUnknown": .bool(outcomeUnknown),
            "retrySafe": .bool(retrySafe)
        ]
        if operationCommitted {
            root["operationCommitted"] = .bool(true)
            root["inspectionRequired"] = .bool(true)
        }
        root["details"] = .object([
            "deletionState": .string(state),
            "operationCommitState": .string(operationCommitState),
            "outcomeUnknown": .bool(outcomeUnknown),
            "retrySafe": .bool(retrySafe),
            "mutationAttempted": .bool(true),
            "targetId": .string(targetID),
            targetField: .string(targetID),
            "cause": iapVersionedStructuredError(error),
            "inspection": .object([
                "tool": .string(inspectionTool),
                "arguments": .object(inspectionArguments),
                "instruction": .string("Inspect this exact resource before another delete attempt.")
            ])
        ])
        return MCPResult.json(.object(root), text: "Error: \(message)", isError: true)
    }

    private func iapVersionedMutationOutcomeIsUnknown(_ error: Error) -> Bool {
        guard let error = error as? ASCError else { return true }
        switch error {
        case .network, .deleteOutcomeUnknown:
            return true
        case .api(_, let statusCode), .apiResponse(_, let statusCode):
            return statusCode == 408 || (500...599).contains(statusCode)
        case .deleteCommittedUnverified:
            return true
        case .authentication, .configuration, .parsing:
            return false
        }
    }

    private func iapVersionedStructuredError(_ error: Error) -> Value {
        if let error = error as? ASCError {
            return error.structuredValue
        }
        return .object([
            "type": .string("unexpected"),
            "message": .string(Redactor.redact(error.localizedDescription))
        ])
    }

    private func formatIAPVersion(_ version: ASCIAPVersion) -> [String: Any] {
        var result: [String: Any] = [
            "id": version.id,
            "type": version.type,
            "version": version.attributes?.version.jsonSafe,
            "state": version.attributes?.state.jsonSafe,
            "iap_id": version.relationships?.inAppPurchase?.data?.id.jsonSafe,
            "image_id": version.relationships?.image?.data?.id.jsonSafe
        ]
        if let images = version.relationships?.images {
            if let data = images.data {
                result["image_ids"] = data.map(\.id)
            }
            result["images_page"] = formatIAPVersionedRelationshipPage(images)
        }
        if let localizations = version.relationships?.localizations {
            if let data = localizations.data {
                result["localization_ids"] = data.map(\.id)
            }
            result["localizations_page"] = formatIAPVersionedRelationshipPage(localizations)
        }
        return result
    }

    private func formatIAPVersionedRelationshipPage(
        _ relationship: ASCIAPVersionPagedRelationship
    ) -> [String: Any] {
        let ids = relationship.data?.map(\.id)
        let total = relationship.meta?.paging.total
        let nextCursor = relationship.meta?.paging.nextCursor
        let truncated = ids.map { ids in
            nextCursor != nil || total.map { $0 > ids.count } == true
        }
        var result: [String: Any] = [
            "total": total.jsonSafe,
            "limit": relationship.meta?.paging.limit.jsonSafe,
            "next_cursor": nextCursor.jsonSafe,
            "truncated": truncated.jsonSafe,
            "data_returned": ids != nil,
            "completeness_known": ids != nil && (total != nil || nextCursor != nil)
        ]
        if let ids {
            result["ids"] = ids
            result["count"] = ids.count
        }
        return result
    }

    private func formatIAPVersionLocalization(_ localization: ASCIAPVersionLocalization) -> [String: Any] {
        [
            "id": localization.id,
            "type": localization.type,
            "locale": localization.attributes?.locale.jsonSafe,
            "name": localization.attributes?.name.jsonSafe,
            "description": localization.attributes?.description.jsonSafe,
            "version_id": localization.relationships?.version?.data?.id.jsonSafe
        ]
    }

    private func formatIAPVersionImage(_ image: ASCIAPVersionImage) -> [String: Any] {
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
}
