import Foundation
import MCP
import os

// MARK: - Tool Handlers
extension ScreenshotsWorker {

    /// Lists screenshot sets for one localization parent
    /// - Returns: JSON array of screenshot sets with display types
    func listScreenshotSets(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateMediaArguments(
                arguments,
                allowed: mediaParentArgumentNames.union([
                    "display_types",
                    "app_store_version_localization_ids",
                    "custom_product_page_localization_ids",
                    "treatment_localization_ids",
                    "limit",
                    "next_url"
                ])
            )
            let parent = try mediaSetParent(from: arguments)
            let response: ASCScreenshotSetsResponse
            let endpoint = try mediaSetCollectionEndpoint(parent: parent, kind: .screenshot)
            var queryParams = ["limit": String(try mediaLimit(arguments["limit"], defaultValue: 25))]
            try applyStringArrayFilter(
                arguments["display_types"],
                fieldName: "display_types",
                appleName: "filter[screenshotDisplayType]",
                allowedValues: Set(Self.screenshotDisplayTypes),
                to: &queryParams
            )
            let requestedDisplayTypes = arguments["display_types"].map {
                Set($0.arrayValue?.compactMap(\.stringValue) ?? [])
            }
            try applyMediaParentFilters(arguments, parent: parent, to: &queryParams)

            let requestedCursor: String?
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                requestedCursor = try mediaContinuationCursor(
                    nextUrl,
                    path: endpoint,
                    query: queryParams,
                    context: "screenshot-set collection request"
                )
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: mediaPaginationScope(path: endpoint, query: queryParams),
                    as: ASCScreenshotSetsResponse.self
                )
            } else {
                requestedCursor = nil
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCScreenshotSetsResponse.self
                )
            }

            let page = try validateMediaCollectionPage(
                links: response.links,
                meta: response.meta,
                dataCount: response.data.count,
                expectedPath: endpoint,
                query: queryParams,
                requestedCursor: requestedCursor,
                requireTotal: false,
                context: "screenshot-set collection"
            )
            try validateScreenshotSets(
                response.data,
                expectedDisplayType: nil,
                allowedDisplayTypes: requestedDisplayTypes,
                expectedParent: parent
            )
            let sets = response.data.map { formatScreenshotSet($0) }

            var result: [String: Any] = [
                "success": true,
                "screenshot_sets": sets,
                "count": sets.count,
                "parent": mediaParentProjection(parent)
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }
            if let total = page.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to list screenshot sets")
        }
    }

    /// Gets one screenshot set
    /// - Returns: JSON with the exact screenshot set
    func getScreenshotSet(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateMediaArguments(arguments, allowed: ["set_id"])
            let setID = try mediaIdentifier("set_id", from: arguments)
            let set = try await fetchScreenshotSet(setID)
            return MCPResult.jsonObject([
                "success": true,
                "screenshot_set": formatScreenshotSet(set)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get screenshot set")
        }
    }

    /// Creates a screenshot set for one localization parent
    /// - Returns: JSON with created screenshot set details
    func createScreenshotSet(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let parent: MediaSetParent
        let displayType: String
        do {
            try validateMediaArguments(
                arguments,
                allowed: mediaParentArgumentNames.union(["display_type"])
            )
            parent = try mediaSetParent(from: arguments)
            displayType = try mediaEnum(
                "display_type",
                from: arguments,
                allowed: Set(Self.screenshotDisplayTypes)
            )
            let existing = try await fetchAllScreenshotSets(parent: parent, displayType: displayType)
            guard existing.isEmpty else {
                return mediaExistingSetFailure(
                    kind: .screenshot,
                    parent: parent,
                    mediaType: displayType,
                    candidates: existing.map(formatScreenshotSet)
                )
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate screenshot set creation")
        }

        let relationships: CreateScreenshotSetRequest.Relationships
        switch parent {
        case .appStoreVersion(let id):
            relationships = .init(
                appStoreVersionLocalization: .init(data: ASCResourceIdentifier(type: "appStoreVersionLocalizations", id: id)),
                appCustomProductPageLocalization: nil,
                appStoreVersionExperimentTreatmentLocalization: nil
            )
        case .customProductPage(let id):
            relationships = .init(
                appStoreVersionLocalization: nil,
                appCustomProductPageLocalization: .init(data: ASCResourceIdentifier(type: "appCustomProductPageLocalizations", id: id)),
                appStoreVersionExperimentTreatmentLocalization: nil
            )
        case .treatment(let id):
            relationships = .init(
                appStoreVersionLocalization: nil,
                appCustomProductPageLocalization: nil,
                appStoreVersionExperimentTreatmentLocalization: .init(data: ASCResourceIdentifier(type: "appStoreVersionExperimentTreatmentLocalizations", id: id))
            )
        }
        let request = CreateScreenshotSetRequest(
            data: CreateScreenshotSetRequest.CreateData(
                attributes: CreateScreenshotSetRequest.Attributes(
                    screenshotDisplayType: displayType
                ),
                relationships: relationships
            )
        )

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(request)
        } catch {
            return mediaPreRequestFailure(
                operation: "create",
                kind: .screenshot,
                parent: parent,
                setID: nil,
                mediaType: displayType,
                error: error
            )
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/appScreenshotSets", body: requestData)
        } catch {
            return await mediaCreateRequestFailure(
                kind: .screenshot,
                parent: parent,
                mediaType: displayType,
                error: error
            )
        }

        let response: ASCScreenshotSetResponse
        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "Screenshot set create"
            )
            response = try JSONDecoder().decode(ASCScreenshotSetResponse.self, from: receipt.data)
            try validateScreenshotSet(
                response.data,
                expectedID: nil,
                expectedDisplayType: displayType,
                expectedParent: parent
            )
            try validateMediaDocumentSelf(
                response.links.`self`,
                expectedPath: try mediaResourcePath(kind: .screenshotSet, id: response.data.id),
                context: "screenshot-set create response"
            )
        } catch {
            return await mediaCreateAcceptedResponseFailure(
                kind: .screenshot,
                parent: parent,
                setID: nil,
                responseSetID: nil,
                mediaType: displayType,
                error: error
            )
        }

        do {
            let confirmed = try await fetchAllScreenshotSets(parent: parent, displayType: displayType)
            guard confirmed.count == 1, confirmed[0].id == response.data.id else {
                throw MediaArgumentError("The parent-scoped screenshot-set postflight did not uniquely confirm the created resource")
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "create",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "createdByInvocation": true,
                "candidateAttributionConfirmed": true,
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "parent": mediaParentProjection(parent),
                "screenshot_set": formatScreenshotSet(confirmed[0])
            ])
        } catch {
            return await mediaCreateAcceptedResponseFailure(
                kind: .screenshot,
                parent: parent,
                setID: response.data.id,
                responseSetID: response.data.id,
                mediaType: displayType,
                error: error
            )
        }
    }

    /// Deletes a screenshot set
    /// - Returns: JSON confirmation
    func deleteScreenshotSet(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let setID: String
        do {
            try validateMediaArguments(arguments, allowed: ["set_id", "confirm_set_id"])
            setID = try mediaIdentifier("set_id", from: arguments)
            let confirmationID = try mediaIdentifier("confirm_set_id", from: arguments)
            guard confirmationID == setID else {
                throw MediaArgumentError("Deleting a screenshot set cascades to all screenshots. Set confirm_set_id to the exact set_id to continue.")
            }
            _ = try await fetchScreenshotSet(setID)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate screenshot set deletion")
        }

        do {
            let receipt = try await httpClient.deleteReceipt(
                "/v1/appScreenshotSets/\(try ASCPathSegment.encode(setID, field: "set_id"))"
            )
            guard receipt.statusCode == 204 else {
                return mediaAcceptedMutationFailure(
                    operation: "delete",
                    kind: .screenshot,
                    setID: setID,
                    error: ASCError.deleteCommittedUnverified(statusCode: receipt.statusCode)
                )
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "delete",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "setId": setID,
                "message": "Screenshot set '\(setID)' deleted"
            ])
        } catch {
            return mediaRequestMutationFailure(
                operation: "delete",
                kind: .screenshot,
                setID: setID,
                error: error
            )
        }
    }

    /// Lists screenshots in a screenshot set
    /// - Returns: JSON array of screenshots with file info and upload status
    func listScreenshots(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateMediaArguments(arguments, allowed: ["set_id", "limit", "next_url"])
            let setId = try mediaIdentifier("set_id", from: arguments)
            let response: ASCScreenshotsResponse
            let endpoint = "/v1/appScreenshotSets/\(try ASCPathSegment.encode(setId, field: "set_id"))/appScreenshots"
            let queryParams = ["limit": String(try mediaLimit(arguments["limit"], defaultValue: 25))]

            let requestedCursor: String?
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                requestedCursor = try mediaContinuationCursor(
                    nextUrl,
                    path: endpoint,
                    query: queryParams,
                    context: "screenshot collection request"
                )
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: mediaPaginationScope(path: endpoint, query: queryParams),
                    as: ASCScreenshotsResponse.self
                )
            } else {
                requestedCursor = nil
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCScreenshotsResponse.self
                )
            }

            let page = try validateMediaCollectionPage(
                links: response.links,
                meta: response.meta,
                dataCount: response.data.count,
                expectedPath: endpoint,
                query: queryParams,
                requestedCursor: requestedCursor,
                requireTotal: false,
                context: "screenshot collection"
            )
            try validateScreenshotResources(response.data, expectedSetID: setId)
            let screenshots = response.data.map { formatScreenshot($0) }

            var result: [String: Any] = [
                "success": true,
                "screenshots": screenshots,
                "count": screenshots.count
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }
            if let total = page.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to list screenshots")
        }
    }

    /// Uploads a screenshot and reconciles its asynchronous processing state
    /// - Returns: JSON with terminal or accepted processing-pending screenshot info
    func uploadScreenshot(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let setID: String
        let filePath: String
        do {
            try validateMediaArguments(arguments, allowed: ["set_id", "file_path"])
            setID = try mediaIdentifier("set_id", from: arguments)
            filePath = try mediaUploadFilePath("file_path", from: arguments)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate screenshot upload")
        }

        let snapshot: UploadFileSnapshot
        do {
            snapshot = try await prepareMediaUploadSnapshot(filePath: filePath)
        } catch {
            return MCPResult.error(error, prefix: "Failed to prepare screenshot upload")
        }
        defer { snapshot.discard() }

        let outcome = await performScreenshotUpload(
            filePath: filePath,
            snapshot: snapshot,
            setID: setID
        )

        return UploadTransactionRecovery.result(
            for: outcome,
            descriptor: screenshotUploadDescriptor(setID: setID),
            format: formatScreenshot
        )
    }

    /// Uploads multiple screenshots to a set sequentially
    /// - Returns: JSON array with results for each file (success or error)
    func uploadScreenshotBatch(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let setID: String
        let filePaths: [String]
        do {
            try validateMediaArguments(arguments, allowed: ["set_id", "file_paths"])
            setID = try mediaIdentifier("set_id", from: arguments)
            let values = try mediaStringArray(
                "file_paths",
                from: arguments,
                minimumCount: 1,
                maximumCount: Self.maximumBatchUploadCount,
                requireCanonicalIDs: false
            )
            filePaths = try values.map { try validateMediaUploadPath($0, fieldName: "file_paths") }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate screenshot batch upload")
        }

        var snapshots: [UploadFileSnapshot] = []
        snapshots.reserveCapacity(filePaths.count)
        do {
            for filePath in filePaths {
                snapshots.append(try await prepareMediaUploadSnapshot(filePath: filePath))
            }
        } catch {
            snapshots.forEach { $0.discard() }
            return MCPResult.error(error, prefix: "Failed to preflight screenshot batch upload")
        }
        defer { snapshots.forEach { $0.discard() } }

        var results: [[String: Any]] = []
        var successCount = 0
        var failCount = 0

        let descriptor = screenshotUploadDescriptor(setID: setID)

        for (filePath, snapshot) in zip(filePaths, snapshots) {
            let fileName = snapshot.fileName
            let outcome = await performScreenshotUpload(
                filePath: filePath,
                snapshot: snapshot,
                setID: setID
            )

            switch outcome {
            case .success(let screenshot, let reconciled):
                var result: [String: Any] = [
                    "file": fileName,
                    "success": true,
                    "screenshot_id": screenshot.id,
                    "state": screenshot.attributes?.assetDeliveryState?.state ?? "unknown"
                ]
                if reconciled {
                    result["reconciled_after_commit"] = true
                }
                results.append(result)
                successCount += 1
            case .processingPending(_, let screenshot, let reconciled):
                var result: [String: Any] = [
                    "file": fileName,
                    "success": true,
                    "screenshot_id": screenshot.id,
                    "state": screenshot.attributes?.assetDeliveryState?.state ?? "unknown",
                    "upload_committed": true,
                    "processing_complete": false,
                    "delivery_pending": true,
                    "retry_safe": false,
                    "inspect_tool": "screenshots_get",
                    "inspect_arguments": ["screenshot_id": screenshot.id]
                ]
                if reconciled {
                    result["reconciled_after_commit"] = true
                }
                results.append(result)
                successCount += 1
            default:
                var result = UploadTransactionRecovery.failurePayload(
                    for: outcome,
                    descriptor: descriptor,
                    format: formatScreenshot
                ) ?? ["success": false, "error": "Unknown upload failure"]
                result["file"] = fileName
                results.append(result)
                failCount += 1
            }
        }

        let response: [String: Any] = [
            "success": failCount == 0,
            "total": filePaths.count,
            "uploaded": successCount,
            "failed": failCount,
            "results": results
        ]

        return MCPResult.jsonObject(response)
    }

    /// Gets details of a specific screenshot
    /// - Returns: JSON with screenshot details
    func getScreenshot(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateMediaArguments(arguments, allowed: ["screenshot_id"])
            let screenshotId = try mediaIdentifier("screenshot_id", from: arguments)
            let endpoint = try mediaResourcePath(kind: .screenshot, id: screenshotId)
            let data = try await httpClient.get(endpoint)
            let screenshot = try decodeScreenshotResponse(
                data,
                expectedID: screenshotId,
                expectedSetID: nil,
                context: "screenshot get response"
            )

            let result = [
                "success": true,
                "screenshot": formatScreenshot(screenshot)
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to get screenshot")
        }
    }

    /// Deletes a screenshot
    /// - Returns: JSON confirmation
    func deleteScreenshot(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let screenshotID: String
        do {
            try validateMediaArguments(arguments, allowed: ["screenshot_id", "confirm_screenshot_id"])
            screenshotID = try mediaIdentifier("screenshot_id", from: arguments)
            let confirmationID = try mediaIdentifier("confirm_screenshot_id", from: arguments)
            guard confirmationID == screenshotID else {
                throw MediaArgumentError("Set confirm_screenshot_id to the exact screenshot_id to continue.")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate screenshot deletion")
        }

        do {
            let receipt = try await httpClient.deleteReceipt(
                "/v1/appScreenshots/\(try ASCPathSegment.encode(screenshotID, field: "screenshot_id"))"
            )
            guard receipt.statusCode == 204 else {
                return mediaAcceptedChildDeleteFailure(kind: .screenshot, resourceID: screenshotID, error: ASCError.deleteCommittedUnverified(statusCode: receipt.statusCode))
            }
            let result = [
                "success": true,
                "operationCommitState": "committed",
                "operationCommitted": true,
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "message": "Screenshot '\(screenshotID)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return mediaRequestChildDeleteFailure(kind: .screenshot, resourceID: screenshotID, error: error)
        }
    }

    /// Reorders screenshots within a screenshot set
    /// - Returns: JSON confirmation
    func reorderScreenshots(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let setID: String
        let requestedIDs: [String]
        do {
            try validateMediaArguments(arguments, allowed: ["set_id", "screenshot_ids"])
            setID = try mediaIdentifier("set_id", from: arguments)
            requestedIDs = try mediaStringArray(
                "screenshot_ids",
                from: arguments,
                minimumCount: 1,
                maximumCount: Self.maximumReorderCount,
                requireCanonicalIDs: true
            )
            let currentIDs = try await fetchAllScreenshotIDs(setID: setID)
            try validateCompleteMembership(
                requestedIDs,
                currentIDs: currentIDs,
                resourceName: "screenshots"
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate screenshot reorder")
        }

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(
                ReorderScreenshotsRequest(
                    data: requestedIDs.map { ASCResourceIdentifier(type: "appScreenshots", id: $0) }
                )
            )
        } catch {
            return mediaPreRequestFailure(
                operation: "reorder",
                kind: .screenshot,
                parent: nil,
                setID: setID,
                mediaType: nil,
                error: error
            )
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(
                "/v1/appScreenshotSets/\(try ASCPathSegment.encode(setID, field: "set_id"))/relationships/appScreenshots",
                body: requestData
            )
        } catch {
            return mediaRequestMutationFailure(
                operation: "reorder",
                kind: .screenshot,
                setID: setID,
                error: error
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 204,
                context: "Screenshot reorder"
            )
            let confirmedIDs = try await fetchAllScreenshotIDs(setID: setID)
            guard confirmedIDs == requestedIDs else {
                throw MediaArgumentError("The screenshot order returned by the full postflight does not match the requested order")
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "reorder",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "setId": setID,
                "order": requestedIDs
            ])
        } catch {
            return mediaAcceptedMutationFailure(
                operation: "reorder",
                kind: .screenshot,
                setID: setID,
                error: error
            )
        }
    }

    /// Lists app preview sets for one localization parent
    /// - Returns: JSON array of preview sets with preview types
    func listPreviewSets(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateMediaArguments(
                arguments,
                allowed: mediaParentArgumentNames.union([
                    "preview_types",
                    "app_store_version_localization_ids",
                    "custom_product_page_localization_ids",
                    "treatment_localization_ids",
                    "limit",
                    "next_url"
                ])
            )
            let parent = try mediaSetParent(from: arguments)
            let response: ASCPreviewSetsResponse
            let endpoint = try mediaSetCollectionEndpoint(parent: parent, kind: .preview)
            var queryParams = ["limit": String(try mediaLimit(arguments["limit"], defaultValue: 25))]
            try applyStringArrayFilter(
                arguments["preview_types"],
                fieldName: "preview_types",
                appleName: "filter[previewType]",
                allowedValues: Set(Self.previewTypes),
                to: &queryParams
            )
            let requestedPreviewTypes = arguments["preview_types"].map {
                Set($0.arrayValue?.compactMap(\.stringValue) ?? [])
            }
            try applyMediaParentFilters(arguments, parent: parent, to: &queryParams)

            let requestedCursor: String?
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                requestedCursor = try mediaContinuationCursor(
                    nextUrl,
                    path: endpoint,
                    query: queryParams,
                    context: "app-preview-set collection request"
                )
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: mediaPaginationScope(path: endpoint, query: queryParams),
                    as: ASCPreviewSetsResponse.self
                )
            } else {
                requestedCursor = nil
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCPreviewSetsResponse.self
                )
            }

            let page = try validateMediaCollectionPage(
                links: response.links,
                meta: response.meta,
                dataCount: response.data.count,
                expectedPath: endpoint,
                query: queryParams,
                requestedCursor: requestedCursor,
                requireTotal: false,
                context: "app-preview-set collection"
            )
            try validatePreviewSets(
                response.data,
                expectedPreviewType: nil,
                allowedPreviewTypes: requestedPreviewTypes,
                expectedParent: parent
            )
            let sets = response.data.map { formatPreviewSet($0) }

            var result: [String: Any] = [
                "success": true,
                "preview_sets": sets,
                "count": sets.count,
                "parent": mediaParentProjection(parent)
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }
            if let total = page.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to list preview sets")
        }
    }

    /// Gets one app preview set
    /// - Returns: JSON with the exact app preview set
    func getPreviewSet(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateMediaArguments(arguments, allowed: ["set_id"])
            let setID = try mediaIdentifier("set_id", from: arguments)
            let set = try await fetchPreviewSet(setID)
            return MCPResult.jsonObject([
                "success": true,
                "preview_set": formatPreviewSet(set)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get app preview set")
        }
    }

    /// Creates an app preview set for one localization parent
    /// - Returns: JSON with created preview set details
    func createPreviewSet(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let parent: MediaSetParent
        let previewType: String
        do {
            try validateMediaArguments(
                arguments,
                allowed: mediaParentArgumentNames.union(["preview_type"])
            )
            parent = try mediaSetParent(from: arguments)
            previewType = try mediaEnum(
                "preview_type",
                from: arguments,
                allowed: Set(Self.previewTypes)
            )
            let existing = try await fetchAllPreviewSets(parent: parent, previewType: previewType)
            guard existing.isEmpty else {
                return mediaExistingSetFailure(
                    kind: .preview,
                    parent: parent,
                    mediaType: previewType,
                    candidates: existing.map(formatPreviewSet)
                )
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate app preview set creation")
        }

        let relationships: CreatePreviewSetRequest.Relationships
        switch parent {
        case .appStoreVersion(let id):
            relationships = .init(
                appStoreVersionLocalization: .init(data: ASCResourceIdentifier(type: "appStoreVersionLocalizations", id: id)),
                appCustomProductPageLocalization: nil,
                appStoreVersionExperimentTreatmentLocalization: nil
            )
        case .customProductPage(let id):
            relationships = .init(
                appStoreVersionLocalization: nil,
                appCustomProductPageLocalization: .init(data: ASCResourceIdentifier(type: "appCustomProductPageLocalizations", id: id)),
                appStoreVersionExperimentTreatmentLocalization: nil
            )
        case .treatment(let id):
            relationships = .init(
                appStoreVersionLocalization: nil,
                appCustomProductPageLocalization: nil,
                appStoreVersionExperimentTreatmentLocalization: .init(data: ASCResourceIdentifier(type: "appStoreVersionExperimentTreatmentLocalizations", id: id))
            )
        }
        let request = CreatePreviewSetRequest(
            data: CreatePreviewSetRequest.CreateData(
                attributes: CreatePreviewSetRequest.Attributes(
                    previewType: previewType
                ),
                relationships: relationships
            )
        )

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(request)
        } catch {
            return mediaPreRequestFailure(
                operation: "create",
                kind: .preview,
                parent: parent,
                setID: nil,
                mediaType: previewType,
                error: error
            )
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.postReceipt("/v1/appPreviewSets", body: requestData)
        } catch {
            return await mediaCreateRequestFailure(
                kind: .preview,
                parent: parent,
                mediaType: previewType,
                error: error
            )
        }

        let response: ASCPreviewSetResponse
        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 201,
                context: "App preview set create"
            )
            response = try JSONDecoder().decode(ASCPreviewSetResponse.self, from: receipt.data)
            try validatePreviewSet(
                response.data,
                expectedID: nil,
                expectedPreviewType: previewType,
                expectedParent: parent
            )
            try validateMediaDocumentSelf(
                response.links.`self`,
                expectedPath: try mediaResourcePath(kind: .previewSet, id: response.data.id),
                context: "app-preview-set create response"
            )
        } catch {
            return await mediaCreateAcceptedResponseFailure(
                kind: .preview,
                parent: parent,
                setID: nil,
                responseSetID: nil,
                mediaType: previewType,
                error: error
            )
        }

        do {
            let confirmed = try await fetchAllPreviewSets(parent: parent, previewType: previewType)
            guard confirmed.count == 1, confirmed[0].id == response.data.id else {
                throw MediaArgumentError("The parent-scoped preview-set postflight did not uniquely confirm the created resource")
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "create",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "createdByInvocation": true,
                "candidateAttributionConfirmed": true,
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "parent": mediaParentProjection(parent),
                "preview_set": formatPreviewSet(confirmed[0])
            ])
        } catch {
            return await mediaCreateAcceptedResponseFailure(
                kind: .preview,
                parent: parent,
                setID: response.data.id,
                responseSetID: response.data.id,
                mediaType: previewType,
                error: error
            )
        }
    }

    /// Deletes an app preview set
    /// - Returns: JSON confirmation
    func deletePreviewSet(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let setID: String
        do {
            try validateMediaArguments(arguments, allowed: ["set_id", "confirm_set_id"])
            setID = try mediaIdentifier("set_id", from: arguments)
            let confirmationID = try mediaIdentifier("confirm_set_id", from: arguments)
            guard confirmationID == setID else {
                throw MediaArgumentError("Deleting an app preview set cascades to all previews. Set confirm_set_id to the exact set_id to continue.")
            }
            _ = try await fetchPreviewSet(setID)
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate app preview set deletion")
        }

        do {
            let receipt = try await httpClient.deleteReceipt(
                "/v1/appPreviewSets/\(try ASCPathSegment.encode(setID, field: "set_id"))"
            )
            guard receipt.statusCode == 204 else {
                return mediaAcceptedMutationFailure(
                    operation: "delete",
                    kind: .preview,
                    setID: setID,
                    error: ASCError.deleteCommittedUnverified(statusCode: receipt.statusCode)
                )
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "delete",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "setId": setID,
                "message": "Preview set '\(setID)' deleted"
            ])
        } catch {
            return mediaRequestMutationFailure(
                operation: "delete",
                kind: .preview,
                setID: setID,
                error: error
            )
        }
    }

    /// Uploads an app preview and reconciles its asynchronous processing state
    /// - Returns: JSON with terminal or accepted processing-pending preview info
    func uploadPreview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let setID: String
        let filePath: String
        let mimeType: NullableAttributeValue?
        let previewFrameTimeCode: NullableAttributeValue?
        do {
            try validateMediaArguments(
                arguments,
                allowed: ["set_id", "file_path", "mime_type", "preview_frame_time_code"]
            )
            setID = try mediaIdentifier("set_id", from: arguments)
            filePath = try mediaUploadFilePath("file_path", from: arguments)
            mimeType = try nullablePreviewMimeType(arguments["mime_type"])
            previewFrameTimeCode = try nullableNonemptyString(
                arguments["preview_frame_time_code"],
                fieldName: "preview_frame_time_code"
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate app preview upload")
        }

        let snapshot: UploadFileSnapshot
        do {
            snapshot = try await prepareMediaUploadSnapshot(filePath: filePath)
        } catch {
            return MCPResult.error(error, prefix: "Failed to prepare app preview upload")
        }
        defer { snapshot.discard() }

        let outcome = await performPreviewUpload(
            filePath: filePath,
            snapshot: snapshot,
            setID: setID,
            mimeType: mimeType,
            previewFrameTimeCode: previewFrameTimeCode
        )

        return UploadTransactionRecovery.result(
            for: outcome,
            descriptor: previewUploadDescriptor(setID: setID),
            format: formatPreview
        )
    }

    /// Gets details of a specific app preview
    /// - Returns: JSON with preview details
    func getPreview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateMediaArguments(arguments, allowed: ["preview_id"])
            let previewId = try mediaIdentifier("preview_id", from: arguments)
            let endpoint = try mediaResourcePath(kind: .preview, id: previewId)
            let data = try await httpClient.get(endpoint)
            let preview = try decodePreviewResponse(
                data,
                expectedID: previewId,
                expectedSetID: nil,
                context: "app preview get response"
            )

            let result = [
                "success": true,
                "preview": formatPreview(preview)
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to get preview")
        }
    }

    /// Lists app previews in a preview set
    /// - Returns: JSON array of previews with file info and upload status
    func listPreviews(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            try validateMediaArguments(arguments, allowed: ["set_id", "limit", "next_url"])
            let setId = try mediaIdentifier("set_id", from: arguments)
            let response: ASCPreviewsResponse
            let endpoint = "/v1/appPreviewSets/\(try ASCPathSegment.encode(setId, field: "set_id"))/appPreviews"
            let queryParams = ["limit": String(try mediaLimit(arguments["limit"], defaultValue: 25))]

            let requestedCursor: String?
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                requestedCursor = try mediaContinuationCursor(
                    nextUrl,
                    path: endpoint,
                    query: queryParams,
                    context: "app-preview collection request"
                )
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: mediaPaginationScope(path: endpoint, query: queryParams),
                    as: ASCPreviewsResponse.self
                )
            } else {
                requestedCursor = nil
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCPreviewsResponse.self
                )
            }

            let page = try validateMediaCollectionPage(
                links: response.links,
                meta: response.meta,
                dataCount: response.data.count,
                expectedPath: endpoint,
                query: queryParams,
                requestedCursor: requestedCursor,
                requireTotal: false,
                context: "app-preview collection"
            )
            try validatePreviewResources(response.data, expectedSetID: setId)
            let previews = response.data.map { formatPreview($0) }

            var result: [String: Any] = [
                "success": true,
                "previews": previews,
                "count": previews.count
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }
            if let total = page.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to list previews")
        }
    }

    /// Deletes an app preview
    /// - Returns: JSON confirmation
    func deletePreview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let previewID: String
        do {
            try validateMediaArguments(arguments, allowed: ["preview_id", "confirm_preview_id"])
            previewID = try mediaIdentifier("preview_id", from: arguments)
            let confirmationID = try mediaIdentifier("confirm_preview_id", from: arguments)
            guard confirmationID == previewID else {
                throw MediaArgumentError("Set confirm_preview_id to the exact preview_id to continue.")
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate app preview deletion")
        }

        do {
            let receipt = try await httpClient.deleteReceipt(
                "/v1/appPreviews/\(try ASCPathSegment.encode(previewID, field: "preview_id"))"
            )
            guard receipt.statusCode == 204 else {
                return mediaAcceptedChildDeleteFailure(kind: .preview, resourceID: previewID, error: ASCError.deleteCommittedUnverified(statusCode: receipt.statusCode))
            }
            let result = [
                "success": true,
                "operationCommitState": "committed",
                "operationCommitted": true,
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "message": "Preview '\(previewID)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return mediaRequestChildDeleteFailure(kind: .preview, resourceID: previewID, error: error)
        }
    }

    /// Reorders app previews within an app preview set
    /// - Returns: JSON confirmation with the verified final order
    func reorderPreviews(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let setID: String
        let requestedIDs: [String]
        do {
            try validateMediaArguments(arguments, allowed: ["set_id", "preview_ids"])
            setID = try mediaIdentifier("set_id", from: arguments)
            requestedIDs = try mediaStringArray(
                "preview_ids",
                from: arguments,
                minimumCount: 1,
                maximumCount: Self.maximumReorderCount,
                requireCanonicalIDs: true
            )
            let currentIDs = try await fetchAllPreviewIDs(setID: setID)
            try validateCompleteMembership(
                requestedIDs,
                currentIDs: currentIDs,
                resourceName: "app previews"
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate app preview reorder")
        }

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(
                ReorderPreviewsRequest(
                    data: requestedIDs.map { ASCResourceIdentifier(type: "appPreviews", id: $0) }
                )
            )
        } catch {
            return mediaPreRequestFailure(
                operation: "reorder",
                kind: .preview,
                parent: nil,
                setID: setID,
                mediaType: nil,
                error: error
            )
        }

        let receipt: ASCMutationReceipt
        do {
            receipt = try await httpClient.patchReceipt(
                "/v1/appPreviewSets/\(try ASCPathSegment.encode(setID, field: "set_id"))/relationships/appPreviews",
                body: requestData
            )
        } catch {
            return mediaRequestMutationFailure(
                operation: "reorder",
                kind: .preview,
                setID: setID,
                error: error
            )
        }

        do {
            try ASCNonIdempotentWriteRecovery.validateSuccessfulStatus(
                receipt.statusCode,
                expectedStatusCode: 204,
                context: "App preview reorder"
            )
            let confirmedIDs = try await fetchAllPreviewIDs(setID: setID)
            guard confirmedIDs == requestedIDs else {
                throw MediaArgumentError("The app preview order returned by the full postflight does not match the requested order")
            }
            return MCPResult.jsonObject([
                "success": true,
                "operation": "reorder",
                "operationCommitted": true,
                "operationCommitState": "committed",
                "retrySafe": false,
                "statusCode": receipt.statusCode,
                "setId": setID,
                "order": requestedIDs
            ])
        } catch {
            return mediaAcceptedMutationFailure(
                operation: "reorder",
                kind: .preview,
                setID: setID,
                error: error
            )
        }
    }

    // MARK: - Formatting

    private func formatScreenshotSet(_ set: ASCScreenshotSet) -> [String: Any] {
        var result: [String: Any] = [
            "id": set.id,
            "type": set.type,
            "screenshotDisplayType": (set.attributes?.screenshotDisplayType).jsonSafe
        ]
        if let selfLink = set.links?.`self` {
            result["selfLink"] = selfLink
        }
        if let parent = formatMediaSetParent(set.relationships) {
            result["parent"] = parent
        }
        return result
    }

    private func formatScreenshot(_ screenshot: ASCScreenshot) -> [String: Any] {
        var result: [String: Any] = [
            "id": screenshot.id,
            "type": screenshot.type,
            "fileName": (screenshot.attributes?.fileName).jsonSafe,
            "fileSize": (screenshot.attributes?.fileSize).jsonSafe,
            "sourceFileChecksum": (screenshot.attributes?.sourceFileChecksum).jsonSafe,
            "assetToken": (screenshot.attributes?.assetToken).jsonSafe,
            "assetType": (screenshot.attributes?.assetType).jsonSafe
        ]

        if let imageAsset = screenshot.attributes?.imageAsset {
            result["imageAsset"] = [
                "templateUrl": imageAsset.templateUrl.jsonSafe,
                "width": imageAsset.width.jsonSafe,
                "height": imageAsset.height.jsonSafe
            ]
        }

        if let deliveryState = screenshot.attributes?.assetDeliveryState {
            result["assetDeliveryState"] = [
                "state": deliveryState.state.jsonSafe,
                "errors": deliveryState.errors?.map { ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe] } ?? [],
                "warnings": deliveryState.warnings?.map { ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe] } ?? []
            ]
        }

        if let uploadOps = screenshot.attributes?.uploadOperations, !uploadOps.isEmpty {
            result["uploadOperationCount"] = uploadOps.count
            result["uploadOperations"] = formatUploadOperations(uploadOps)
        }
        if let selfLink = screenshot.links?.`self` {
            result["selfLink"] = selfLink
        }
        if let set = formatMediaRelationship(screenshot.relationships?.appScreenshotSet) {
            result["screenshotSet"] = set
        }

        return result
    }

    private func formatPreviewSet(_ set: ASCPreviewSet) -> [String: Any] {
        var result: [String: Any] = [
            "id": set.id,
            "type": set.type,
            "previewType": (set.attributes?.previewType).jsonSafe
        ]
        if let selfLink = set.links?.`self` {
            result["selfLink"] = selfLink
        }
        if let parent = formatMediaSetParent(set.relationships) {
            result["parent"] = parent
        }
        return result
    }

    private func formatPreview(_ preview: ASCPreview) -> [String: Any] {
        var result: [String: Any] = [
            "id": preview.id,
            "type": preview.type,
            "fileName": (preview.attributes?.fileName).jsonSafe,
            "fileSize": (preview.attributes?.fileSize).jsonSafe,
            "sourceFileChecksum": (preview.attributes?.sourceFileChecksum).jsonSafe,
            "mimeType": (preview.attributes?.mimeType).jsonSafe,
            "videoUrl": (preview.attributes?.videoUrl).jsonSafe,
            "previewFrameTimeCode": (preview.attributes?.previewFrameTimeCode).jsonSafe
        ]

        if let previewImage = preview.attributes?.previewImage {
            result["previewImage"] = [
                "templateUrl": previewImage.templateUrl.jsonSafe,
                "width": previewImage.width.jsonSafe,
                "height": previewImage.height.jsonSafe
            ]
        }

        if let previewFrameImage = preview.attributes?.previewFrameImage {
            var frame: [String: Any] = [:]
            if let image = previewFrameImage.image {
                frame["image"] = [
                    "templateUrl": image.templateUrl.jsonSafe,
                    "width": image.width.jsonSafe,
                    "height": image.height.jsonSafe
                ]
            }
            if let state = previewFrameImage.state {
                frame["state"] = [
                    "state": state.state.jsonSafe,
                    "errors": state.errors?.map { ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe] } ?? [],
                    "warnings": state.warnings?.map { ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe] } ?? []
                ]
            }
            result["previewFrameImage"] = frame
        }

        if let deliveryState = preview.attributes?.assetDeliveryState {
            result["assetDeliveryState"] = [
                "state": deliveryState.state.jsonSafe,
                "errors": deliveryState.errors?.map { ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe] } ?? [],
                "warnings": deliveryState.warnings?.map { ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe] } ?? []
            ]
        }

        if let deliveryState = preview.attributes?.videoDeliveryState {
            result["videoDeliveryState"] = [
                "state": deliveryState.state.jsonSafe,
                "errors": deliveryState.errors?.map { ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe] } ?? [],
                "warnings": deliveryState.warnings?.map { ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe] } ?? []
            ]
        }

        if let uploadOps = preview.attributes?.uploadOperations, !uploadOps.isEmpty {
            result["uploadOperationCount"] = uploadOps.count
            result["uploadOperations"] = formatUploadOperations(uploadOps)
        }
        if let selfLink = preview.links?.`self` {
            result["selfLink"] = selfLink
        }
        if let set = formatMediaRelationship(preview.relationships?.appPreviewSet) {
            result["previewSet"] = set
        }

        return result
    }

    private func formatMediaSetParent(_ relationships: ASCScreenshotSetRelationships?) -> [String: Any]? {
        formatMediaRelationship(relationships?.appStoreVersionLocalization)
            ?? formatMediaRelationship(relationships?.appCustomProductPageLocalization)
            ?? formatMediaRelationship(relationships?.appStoreVersionExperimentTreatmentLocalization)
    }

    private func formatMediaSetParent(_ relationships: ASCPreviewSetRelationships?) -> [String: Any]? {
        formatMediaRelationship(relationships?.appStoreVersionLocalization)
            ?? formatMediaRelationship(relationships?.appCustomProductPageLocalization)
            ?? formatMediaRelationship(relationships?.appStoreVersionExperimentTreatmentLocalization)
    }

    private func formatMediaRelationship(_ relationship: ASCRelationship?) -> [String: Any]? {
        guard let data = relationship?.data else { return nil }
        return ["type": data.type, "id": data.id]
    }

    private func formatUploadOperations(_ operations: [ASCUploadOperation]) -> [[String: Any]] {
        operations.map { operation in
            [
                "method": operation.method.jsonSafe,
                "length": operation.length.jsonSafe,
                "offset": operation.offset.jsonSafe
            ]
        }
    }

    private struct MediaArgumentError: LocalizedError {
        let message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? { message }
    }

    private enum MediaSetKind {
        case screenshot
        case preview

        var setResourceType: String {
            switch self {
            case .screenshot: "appScreenshotSets"
            case .preview: "appPreviewSets"
            }
        }

        var listTool: String {
            switch self {
            case .screenshot: "screenshots_list_sets"
            case .preview: "screenshots_list_preview_sets"
            }
        }

        var getTool: String {
            switch self {
            case .screenshot: "screenshots_get_set"
            case .preview: "screenshots_get_preview_set"
            }
        }

        var listChildrenTool: String {
            switch self {
            case .screenshot: "screenshots_list"
            case .preview: "screenshots_list_previews"
            }
        }

        var getChildTool: String {
            switch self {
            case .screenshot: "screenshots_get"
            case .preview: "screenshots_get_preview"
            }
        }

        var childIDArgument: String {
            switch self {
            case .screenshot: "screenshot_id"
            case .preview: "preview_id"
            }
        }

        var mediaFilterArgument: String {
            switch self {
            case .screenshot: "display_types"
            case .preview: "preview_types"
            }
        }
    }

    private enum MediaResourceKind {
        case screenshotSet
        case previewSet
        case screenshot
        case preview
    }

    private struct MediaCollectionPageValidation {
        let total: Int?
        let nextURL: String?
        let nextCursor: String?
    }

    private enum MediaSetParent {
        case appStoreVersion(String)
        case customProductPage(String)
        case treatment(String)

        var id: String {
            switch self {
            case .appStoreVersion(let id), .customProductPage(let id), .treatment(let id): id
            }
        }

        var resourceType: String {
            switch self {
            case .appStoreVersion: "appStoreVersionLocalizations"
            case .customProductPage: "appCustomProductPageLocalizations"
            case .treatment: "appStoreVersionExperimentTreatmentLocalizations"
            }
        }

        var canonicalArgumentName: String {
            switch self {
            case .appStoreVersion: "app_store_version_localization_id"
            case .customProductPage: "custom_product_page_localization_id"
            case .treatment: "treatment_localization_id"
            }
        }
    }

    private var mediaParentArgumentNames: Set<String> {
        [
            "localization_id",
            "app_store_version_localization_id",
            "custom_product_page_localization_id",
            "treatment_localization_id"
        ]
    }

    private func mediaSetParent(from arguments: [String: Value]) throws -> MediaSetParent {
        var parents: [MediaSetParent] = []
        if arguments["localization_id"] != nil {
            parents.append(.appStoreVersion(try mediaIdentifier("localization_id", from: arguments)))
        }
        if arguments["app_store_version_localization_id"] != nil {
            parents.append(.appStoreVersion(try mediaIdentifier("app_store_version_localization_id", from: arguments)))
        }
        if arguments["custom_product_page_localization_id"] != nil {
            parents.append(.customProductPage(try mediaIdentifier("custom_product_page_localization_id", from: arguments)))
        }
        if arguments["treatment_localization_id"] != nil {
            parents.append(.treatment(try mediaIdentifier("treatment_localization_id", from: arguments)))
        }
        guard parents.count == 1 else {
            throw MediaArgumentError("Provide exactly one localization parent: localization_id, app_store_version_localization_id, custom_product_page_localization_id, or treatment_localization_id")
        }
        return parents[0]
    }

    private func mediaSetCollectionEndpoint(parent: MediaSetParent, kind: MediaSetKind) throws -> String {
        switch (parent, kind) {
        case (.appStoreVersion, .screenshot):
            return "/v1/appStoreVersionLocalizations/\(try ASCPathSegment.encode(parent.id, field: parent.canonicalArgumentName))/appScreenshotSets"
        case (.customProductPage, .screenshot):
            return "/v1/appCustomProductPageLocalizations/\(try ASCPathSegment.encode(parent.id, field: parent.canonicalArgumentName))/appScreenshotSets"
        case (.treatment, .screenshot):
            return "/v1/appStoreVersionExperimentTreatmentLocalizations/\(try ASCPathSegment.encode(parent.id, field: parent.canonicalArgumentName))/appScreenshotSets"
        case (.appStoreVersion, .preview):
            return "/v1/appStoreVersionLocalizations/\(try ASCPathSegment.encode(parent.id, field: parent.canonicalArgumentName))/appPreviewSets"
        case (.customProductPage, .preview):
            return "/v1/appCustomProductPageLocalizations/\(try ASCPathSegment.encode(parent.id, field: parent.canonicalArgumentName))/appPreviewSets"
        case (.treatment, .preview):
            return "/v1/appStoreVersionExperimentTreatmentLocalizations/\(try ASCPathSegment.encode(parent.id, field: parent.canonicalArgumentName))/appPreviewSets"
        }
    }

    private func mediaParentProjection(_ parent: MediaSetParent) -> [String: Any] {
        ["type": parent.resourceType, "id": parent.id]
    }

    private func validateMediaArguments(_ arguments: [String: Value], allowed: Set<String>) throws {
        let unsupported = Set(arguments.keys).subtracting(allowed).sorted()
        guard unsupported.isEmpty else {
            throw MediaArgumentError("Unsupported parameter(s): \(unsupported.joined(separator: ", "))")
        }
    }

    private func mediaIdentifier(_ name: String, from arguments: [String: Value]) throws -> String {
        guard let value = arguments[name]?.stringValue else {
            throw MediaArgumentError("'\(name)' must be a string")
        }
        let encoded = try ASCPathSegment.encode(value, field: name)
        guard encoded == value else {
            throw MediaArgumentError("'\(name)' must be a canonical App Store Connect resource ID")
        }
        return value
    }

    private func mediaEnum(
        _ name: String,
        from arguments: [String: Value],
        allowed: Set<String>
    ) throws -> String {
        guard let value = arguments[name]?.stringValue else {
            throw MediaArgumentError("'\(name)' must be a string")
        }
        guard allowed.contains(value) else {
            throw MediaArgumentError("Unsupported value for '\(name)': \(value)")
        }
        return value
    }

    private func mediaLimit(_ value: Value?, defaultValue: Int) throws -> Int {
        guard let value else { return defaultValue }
        guard let limit = value.intValue, (1...200).contains(limit) else {
            throw MediaArgumentError("'limit' must be an integer from 1 through 200")
        }
        return limit
    }

    private func mediaStringArray(
        _ name: String,
        from arguments: [String: Value],
        minimumCount: Int,
        maximumCount: Int,
        requireCanonicalIDs: Bool,
        rejectCommas: Bool = false
    ) throws -> [String] {
        guard let rawValues = arguments[name]?.arrayValue else {
            throw MediaArgumentError("'\(name)' must be an array of strings")
        }
        guard (minimumCount...maximumCount).contains(rawValues.count) else {
            throw MediaArgumentError("'\(name)' must contain between \(minimumCount) and \(maximumCount) values")
        }
        var values: [String] = []
        values.reserveCapacity(rawValues.count)
        for (index, rawValue) in rawValues.enumerated() {
            guard let value = rawValue.stringValue,
                  !value.isEmpty,
                  value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw MediaArgumentError("'\(name)[\(index)]' must be a non-empty string without surrounding whitespace")
            }
            if rejectCommas, value.contains(",") {
                throw MediaArgumentError("'\(name)[\(index)]' must not contain commas")
            }
            if requireCanonicalIDs {
                let encoded = try ASCPathSegment.encode(value, field: "\(name)[\(index)]")
                guard encoded == value else {
                    throw MediaArgumentError("'\(name)[\(index)]' must be a canonical App Store Connect resource ID")
                }
            }
            values.append(value)
        }
        guard Set(values).count == values.count else {
            throw MediaArgumentError("'\(name)' must not contain duplicate values")
        }
        return values
    }

    private func mediaUploadFilePath(
        _ name: String,
        from arguments: [String: Value]
    ) throws -> String {
        guard let value = arguments[name]?.stringValue else {
            throw MediaArgumentError("'\(name)' must be a string")
        }
        return try validateMediaUploadPath(value, fieldName: name)
    }

    private func validateMediaUploadPath(_ path: String, fieldName: String) throws -> String {
        guard !path.isEmpty,
              path == path.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              (path as NSString).isAbsolutePath else {
            throw MediaArgumentError("'\(fieldName)' must be an absolute path without surrounding whitespace or control characters")
        }
        let fileManager = FileManager.default
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: path)
        } catch {
            throw MediaArgumentError("'\(fieldName)' must reference an existing readable regular file")
        }
        guard let fileType = attributes[.type] as? FileAttributeType,
              fileType == .typeRegular,
              fileManager.isReadableFile(atPath: path) else {
            throw MediaArgumentError("'\(fieldName)' must reference an existing readable regular file")
        }
        return path
    }

    private func prepareMediaUploadSnapshot(filePath: String) async throws -> UploadFileSnapshot {
        _ = try validateMediaUploadPath(filePath, fieldName: "file_path")
        let snapshot = try await uploadService.prepareSnapshot(filePath: filePath)
        do {
            let expectedName = URL(fileURLWithPath: filePath).lastPathComponent
            guard !expectedName.isEmpty,
                  snapshot.fileName == expectedName,
                  snapshot.fileSize > 0 else {
                throw MediaArgumentError("The immutable upload snapshot has an invalid file name or size")
            }
            return snapshot
        } catch {
            snapshot.discard()
            throw error
        }
    }

    private func screenshotUploadDescriptor(setID: String) -> UploadRecoveryDescriptor {
        UploadRecoveryDescriptor(
            resourceName: "screenshot",
            successKey: "screenshot",
            idArgument: "screenshot_id",
            getTool: "screenshots_get",
            getIDArgument: "screenshot_id",
            deleteTool: "screenshots_delete",
            deleteConfirmationArgument: "confirm_screenshot_id",
            inspectionTool: "screenshots_list",
            inspectionArguments: ["set_id": setID],
            inspectionPageLimit: 200,
            inspectionNextURLArgument: "next_url",
            reservationFingerprintKey: "reservationFingerprint",
            inspectionCandidateFields: ["fileName", "fileSize"],
            checksumReceiptKey: "sourceFileChecksumReceipt",
            includeChecksumInReservationFingerprint: false
        )
    }

    private func previewUploadDescriptor(setID: String) -> UploadRecoveryDescriptor {
        UploadRecoveryDescriptor(
            resourceName: "app preview",
            successKey: "preview",
            idArgument: "preview_id",
            getTool: "screenshots_get_preview",
            getIDArgument: "preview_id",
            deleteTool: "screenshots_delete_preview",
            deleteConfirmationArgument: "confirm_preview_id",
            inspectionTool: "screenshots_list_previews",
            inspectionArguments: ["set_id": setID],
            inspectionPageLimit: 200,
            inspectionNextURLArgument: "next_url",
            reservationFingerprintKey: "reservationFingerprint",
            inspectionCandidateFields: ["fileName", "fileSize"],
            checksumReceiptKey: "sourceFileChecksumReceipt",
            includeChecksumInReservationFingerprint: false
        )
    }

    private func performScreenshotUpload(
        filePath: String,
        snapshot: UploadFileSnapshot,
        setID: String
    ) async -> UploadTransactionOutcome<ASCScreenshot> {
        let semanticValidation = MediaUploadSemanticValidationState(resourceName: "screenshot")
        let rawOutcome: UploadTransactionOutcome<ASCScreenshot> = await UploadTransactionRecovery.perform(
            filePath: filePath,
            resourceName: "screenshot",
            expectedType: "appScreenshots",
            reservationEndpoint: "/v1/appScreenshots",
            httpClient: httpClient,
            uploadService: uploadService,
            preparedSnapshot: snapshot,
            validateReservedResource: { screenshot, snapshot in
                try validateScreenshotReservation(
                    screenshot,
                    snapshot: snapshot,
                    expectedSetID: setID
                )
            },
            validateReservedResourceAsync: { screenshot, _ in
                guard screenshot.relationships?.appScreenshotSet?.data == nil else { return }
                let ids = try await fetchAllScreenshotIDs(setID: setID)
                guard ids.contains(screenshot.id) else {
                    throw MediaArgumentError("The parent-scoped screenshot inventory did not confirm the reservation ID")
                }
            },
            deliveryPollAttempts: deliveryPollAttempts,
            deliveryPollIntervalNanoseconds: deliveryPollIntervalNanoseconds,
            makeReservationBody: { fileSize, fileName in
                try JSONEncoder().encode(
                    CreateScreenshotRequest(
                        data: CreateScreenshotRequest.CreateData(
                            attributes: CreateScreenshotRequest.Attributes(
                                fileName: fileName,
                                fileSize: fileSize
                            ),
                            relationships: CreateScreenshotRequest.Relationships(
                                appScreenshotSet: CreateScreenshotRequest.ScreenshotSetRelationship(
                                    data: ASCResourceIdentifier(type: "appScreenshotSets", id: setID)
                                )
                            )
                        )
                    )
                )
            },
            decodeReservedResource: { data in
                do {
                    let screenshot = try decodeScreenshotResponse(
                        data,
                        expectedID: nil,
                        expectedSetID: nil,
                        context: "screenshot reservation response"
                    )
                    semanticValidation.establishResourceID(screenshot.id)
                    return screenshot
                } catch {
                    semanticValidation.record(error)
                    throw error
                }
            },
            decodeResource: { data in
                do {
                    let screenshot = try decodeScreenshotResponse(
                        data,
                        expectedID: semanticValidation.expectedResourceID(),
                        expectedSetID: setID,
                        context: "screenshot upload response"
                    )
                    try validateCommittedScreenshotSnapshot(screenshot, snapshot: snapshot)
                    semanticValidation.establishResourceID(screenshot.id)
                    return screenshot
                } catch {
                    semanticValidation.record(error)
                    throw error
                }
            },
            makeCommitBody: { screenshotID, checksum in
                try JSONEncoder().encode(
                    CommitScreenshotRequest(
                        data: CommitScreenshotRequest.CommitData(
                            id: screenshotID,
                            attributes: CommitScreenshotRequest.Attributes(
                                sourceFileChecksum: checksum,
                                uploaded: true
                            )
                        )
                    )
                )
            },
            resourceEndpoint: { try mediaResourcePath(kind: .screenshot, id: $0) }
        )
        return semanticValidation.enforcing(rawOutcome)
    }

    private func performPreviewUpload(
        filePath: String,
        snapshot: UploadFileSnapshot,
        setID: String,
        mimeType: NullableAttributeValue?,
        previewFrameTimeCode: NullableAttributeValue?
    ) async -> UploadTransactionOutcome<ASCPreview> {
        let semanticValidation = MediaUploadSemanticValidationState(resourceName: "app preview")
        let rawOutcome: UploadTransactionOutcome<ASCPreview> = await UploadTransactionRecovery.perform(
            filePath: filePath,
            resourceName: "app preview",
            expectedType: "appPreviews",
            reservationEndpoint: "/v1/appPreviews",
            httpClient: httpClient,
            uploadService: uploadService,
            preparedSnapshot: snapshot,
            validateReservedResource: { preview, snapshot in
                try validatePreviewReservation(
                    preview,
                    snapshot: snapshot,
                    expectedSetID: setID
                )
            },
            validateReservedResourceAsync: { preview, _ in
                guard preview.relationships?.appPreviewSet?.data == nil else { return }
                let ids = try await fetchAllPreviewIDs(setID: setID)
                guard ids.contains(preview.id) else {
                    throw MediaArgumentError("The parent-scoped app-preview inventory did not confirm the reservation ID")
                }
            },
            deliveryPollAttempts: deliveryPollAttempts,
            deliveryPollIntervalNanoseconds: deliveryPollIntervalNanoseconds,
            makeReservationBody: { fileSize, fileName in
                try JSONEncoder().encode(
                    CreatePreviewRequest(
                        data: CreatePreviewRequest.CreateData(
                            attributes: CreatePreviewRequest.Attributes(
                                fileName: fileName,
                                fileSize: fileSize,
                                previewFrameTimeCode: previewFrameTimeCode,
                                mimeType: mimeType
                            ),
                            relationships: CreatePreviewRequest.Relationships(
                                appPreviewSet: CreatePreviewRequest.PreviewSetRelationship(
                                    data: ASCResourceIdentifier(type: "appPreviewSets", id: setID)
                                )
                            )
                        )
                    )
                )
            },
            decodeReservedResource: { data in
                do {
                    let preview = try decodePreviewResponse(
                        data,
                        expectedID: nil,
                        expectedSetID: nil,
                        context: "app preview reservation response"
                    )
                    semanticValidation.establishResourceID(preview.id)
                    return preview
                } catch {
                    semanticValidation.record(error)
                    throw error
                }
            },
            decodeResource: { data in
                do {
                    let preview = try decodePreviewResponse(
                        data,
                        expectedID: semanticValidation.expectedResourceID(),
                        expectedSetID: setID,
                        context: "app preview upload response"
                    )
                    try validateCommittedPreviewSnapshot(preview, snapshot: snapshot)
                    semanticValidation.establishResourceID(preview.id)
                    return preview
                } catch {
                    semanticValidation.record(error)
                    throw error
                }
            },
            makeCommitBody: { previewID, checksum in
                try JSONEncoder().encode(
                    CommitPreviewRequest(
                        data: CommitPreviewRequest.CommitData(
                            id: previewID,
                            attributes: CommitPreviewRequest.Attributes(
                                sourceFileChecksum: checksum,
                                previewFrameTimeCode: previewFrameTimeCode,
                                uploaded: true
                            )
                        )
                    )
                )
            },
            resourceEndpoint: { try mediaResourcePath(kind: .preview, id: $0) }
        )
        return semanticValidation.enforcing(rawOutcome)
    }

    private func validateScreenshotReservation(
        _ screenshot: ASCScreenshot,
        snapshot: UploadFileSnapshot,
        expectedSetID: String
    ) throws {
        try validateScreenshotResource(
            screenshot,
            expectedID: nil,
            expectedSetID: expectedSetID
        )
        guard screenshot.attributes?.fileName == snapshot.fileName,
              screenshot.attributes?.fileSize == snapshot.fileSize,
              screenshot.attributes?.assetDeliveryState?.state == "AWAITING_UPLOAD" else {
            throw MediaArgumentError("Screenshot reservation does not match the immutable snapshot, parent set, or AWAITING_UPLOAD state")
        }
        if let checksum = screenshot.attributes?.sourceFileChecksum,
           checksum.caseInsensitiveCompare(snapshot.md5Checksum) != .orderedSame {
            throw MediaArgumentError("Screenshot reservation source-file checksum does not match the immutable snapshot")
        }
    }

    private func validatePreviewReservation(
        _ preview: ASCPreview,
        snapshot: UploadFileSnapshot,
        expectedSetID: String
    ) throws {
        try validatePreviewResource(
            preview,
            expectedID: nil,
            expectedSetID: expectedSetID
        )
        let state = preview.attributes?.videoDeliveryState?.state
            ?? preview.attributes?.assetDeliveryState?.state
        guard preview.attributes?.fileName == snapshot.fileName,
              preview.attributes?.fileSize == snapshot.fileSize,
              state == "AWAITING_UPLOAD" else {
            throw MediaArgumentError("App preview reservation does not match the immutable snapshot, parent set, or AWAITING_UPLOAD state")
        }
        if let checksum = preview.attributes?.sourceFileChecksum,
           checksum.caseInsensitiveCompare(snapshot.md5Checksum) != .orderedSame {
            throw MediaArgumentError("App preview reservation source-file checksum does not match the immutable snapshot")
        }
    }

    private func validateCommittedScreenshotSnapshot(
        _ screenshot: ASCScreenshot,
        snapshot: UploadFileSnapshot
    ) throws {
        try validateCommittedMediaSnapshot(
            fileName: screenshot.attributes?.fileName,
            fileSize: screenshot.attributes?.fileSize,
            checksum: screenshot.attributes?.sourceFileChecksum,
            snapshot: snapshot,
            context: "screenshot commit or reconciliation response"
        )
    }

    private func validateCommittedPreviewSnapshot(
        _ preview: ASCPreview,
        snapshot: UploadFileSnapshot
    ) throws {
        try validateCommittedMediaSnapshot(
            fileName: preview.attributes?.fileName,
            fileSize: preview.attributes?.fileSize,
            checksum: preview.attributes?.sourceFileChecksum,
            snapshot: snapshot,
            context: "app preview commit or reconciliation response"
        )
    }

    private func validateCommittedMediaSnapshot(
        fileName: String?,
        fileSize: Int?,
        checksum: String?,
        snapshot: UploadFileSnapshot,
        context: String
    ) throws {
        if let fileName, fileName != snapshot.fileName {
            throw MediaArgumentError("Apple returned \(context) for a different file name")
        }
        if let fileSize, fileSize != snapshot.fileSize {
            throw MediaArgumentError("Apple returned \(context) for a different file size")
        }
        if let checksum,
           checksum.caseInsensitiveCompare(snapshot.md5Checksum) != .orderedSame {
            throw MediaArgumentError("Apple returned \(context) with a different source-file checksum")
        }
    }

    private func decodeScreenshotResponse(
        _ data: Data,
        expectedID: String?,
        expectedSetID: String?,
        context: String
    ) throws -> ASCScreenshot {
        let response = try JSONDecoder().decode(ASCScreenshotResponse.self, from: data)
        try validateScreenshotResource(
            response.data,
            expectedID: expectedID,
            expectedSetID: expectedSetID
        )
        try validateMediaDocumentSelf(
            response.links.`self`,
            expectedPath: try mediaResourcePath(kind: .screenshot, id: response.data.id),
            context: context,
            allowQuery: false
        )
        return response.data
    }

    private func decodePreviewResponse(
        _ data: Data,
        expectedID: String?,
        expectedSetID: String?,
        context: String
    ) throws -> ASCPreview {
        let response = try JSONDecoder().decode(ASCPreviewResponse.self, from: data)
        try validatePreviewResource(
            response.data,
            expectedID: expectedID,
            expectedSetID: expectedSetID
        )
        try validateMediaDocumentSelf(
            response.links.`self`,
            expectedPath: try mediaResourcePath(kind: .preview, id: response.data.id),
            context: context,
            allowQuery: false
        )
        return response.data
    }

    private func applyMediaParentFilters(
        _ arguments: [String: Value],
        parent: MediaSetParent,
        to query: inout [String: String]
    ) throws {
        switch parent {
        case .appStoreVersion:
            guard arguments["app_store_version_localization_ids"] == nil else {
                throw MediaArgumentError("'app_store_version_localization_ids' is not supported when the selected parent is an App Store version localization")
            }
            try applyStringArrayFilter(
                arguments["custom_product_page_localization_ids"],
                fieldName: "custom_product_page_localization_ids",
                appleName: "filter[appCustomProductPageLocalization]",
                requireCanonicalIDs: true,
                to: &query
            )
            try applyStringArrayFilter(
                arguments["treatment_localization_ids"],
                fieldName: "treatment_localization_ids",
                appleName: "filter[appStoreVersionExperimentTreatmentLocalization]",
                requireCanonicalIDs: true,
                to: &query
            )
        case .customProductPage:
            guard arguments["custom_product_page_localization_ids"] == nil else {
                throw MediaArgumentError("'custom_product_page_localization_ids' is not supported when the selected parent is a custom product page localization")
            }
            try applyStringArrayFilter(
                arguments["app_store_version_localization_ids"],
                fieldName: "app_store_version_localization_ids",
                appleName: "filter[appStoreVersionLocalization]",
                requireCanonicalIDs: true,
                to: &query
            )
            try applyStringArrayFilter(
                arguments["treatment_localization_ids"],
                fieldName: "treatment_localization_ids",
                appleName: "filter[appStoreVersionExperimentTreatmentLocalization]",
                requireCanonicalIDs: true,
                to: &query
            )
        case .treatment:
            guard arguments["treatment_localization_ids"] == nil else {
                throw MediaArgumentError("'treatment_localization_ids' is not supported when the selected parent is a PPO treatment localization")
            }
            try applyStringArrayFilter(
                arguments["app_store_version_localization_ids"],
                fieldName: "app_store_version_localization_ids",
                appleName: "filter[appStoreVersionLocalization]",
                requireCanonicalIDs: true,
                to: &query
            )
            try applyStringArrayFilter(
                arguments["custom_product_page_localization_ids"],
                fieldName: "custom_product_page_localization_ids",
                appleName: "filter[appCustomProductPageLocalization]",
                requireCanonicalIDs: true,
                to: &query
            )
        }
    }

    private func applyStringArrayFilter(
        _ value: Value?,
        fieldName: String,
        appleName: String,
        allowedValues: Set<String>? = nil,
        requireCanonicalIDs: Bool = false,
        to query: inout [String: String]
    ) throws {
        guard let value else {
            return
        }
        guard let rawValues = value.arrayValue else {
            throw ASCError.parsing("'\(fieldName)' must be an array of strings")
        }
        let values = rawValues.compactMap(\.stringValue)
        guard values.count == rawValues.count else {
            throw ASCError.parsing("'\(fieldName)' must contain only strings")
        }
        guard !values.isEmpty else {
            throw ASCError.parsing("'\(fieldName)' must contain at least one value")
        }
        guard values.allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }) else {
            throw ASCError.parsing("'\(fieldName)' must contain only non-empty values without surrounding whitespace")
        }
        guard values.allSatisfy({ !$0.contains(",") }) else {
            throw ASCError.parsing("'\(fieldName)' values must not contain commas")
        }
        guard Set(values).count == values.count else {
            throw ASCError.parsing("'\(fieldName)' must not contain duplicate values")
        }
        if requireCanonicalIDs {
            for (index, value) in values.enumerated() {
                let encoded = try ASCPathSegment.encode(value, field: "\(fieldName)[\(index)]")
                guard encoded == value else {
                    throw ASCError.parsing("'\(fieldName)' must contain canonical App Store Connect resource IDs")
                }
            }
        }
        if let allowedValues {
            let unsupported = values.filter { !allowedValues.contains($0) }
            guard unsupported.isEmpty else {
                throw ASCError.parsing("Unsupported value(s) for '\(fieldName)': \(unsupported.joined(separator: ", "))")
            }
        }
        query[appleName] = values.joined(separator: ",")
    }

    private func validateScreenshotSet(
        _ set: ASCScreenshotSet,
        expectedID: String?,
        expectedDisplayType: String?,
        expectedParent: MediaSetParent? = nil
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: set.type,
            id: set.id,
            expectedType: "appScreenshotSets",
            expectedID: expectedID,
            context: "screenshot set"
        )
        try validateMediaResourceSelf(
            set.links?.`self`,
            kind: .screenshotSet,
            id: set.id,
            context: "screenshot set"
        )
        try validateMediaSetLineage(
            appStoreVersion: set.relationships?.appStoreVersionLocalization,
            customProductPage: set.relationships?.appCustomProductPageLocalization,
            treatment: set.relationships?.appStoreVersionExperimentTreatmentLocalization,
            expectedParent: expectedParent,
            context: "screenshot set"
        )
        if let value = set.attributes?.screenshotDisplayType {
            guard Self.screenshotDisplayTypes.contains(value) else {
                throw MediaArgumentError("Apple returned an unsupported screenshotDisplayType")
            }
        }
        if let expectedDisplayType {
            guard set.attributes?.screenshotDisplayType == expectedDisplayType else {
                throw MediaArgumentError("Apple returned a screenshot set with an unexpected display type")
            }
        }
    }

    private func validateScreenshotSets(
        _ sets: [ASCScreenshotSet],
        expectedDisplayType: String?,
        allowedDisplayTypes: Set<String>? = nil,
        expectedParent: MediaSetParent? = nil
    ) throws {
        var identities = Set<String>()
        for set in sets {
            try validateScreenshotSet(
                set,
                expectedID: nil,
                expectedDisplayType: expectedDisplayType,
                expectedParent: expectedParent
            )
            if let allowedDisplayTypes {
                guard let displayType = set.attributes?.screenshotDisplayType,
                      allowedDisplayTypes.contains(displayType) else {
                    throw MediaArgumentError("Apple returned a screenshot set outside the requested display_types filter")
                }
            }
            guard identities.insert(set.id).inserted else {
                throw MediaArgumentError("Apple returned duplicate screenshot-set identities")
            }
        }
    }

    private func validatePreviewSet(
        _ set: ASCPreviewSet,
        expectedID: String?,
        expectedPreviewType: String?,
        expectedParent: MediaSetParent? = nil
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: set.type,
            id: set.id,
            expectedType: "appPreviewSets",
            expectedID: expectedID,
            context: "app preview set"
        )
        try validateMediaResourceSelf(
            set.links?.`self`,
            kind: .previewSet,
            id: set.id,
            context: "app preview set"
        )
        try validateMediaSetLineage(
            appStoreVersion: set.relationships?.appStoreVersionLocalization,
            customProductPage: set.relationships?.appCustomProductPageLocalization,
            treatment: set.relationships?.appStoreVersionExperimentTreatmentLocalization,
            expectedParent: expectedParent,
            context: "app preview set"
        )
        if let value = set.attributes?.previewType {
            guard Self.previewTypes.contains(value) else {
                throw MediaArgumentError("Apple returned an unsupported previewType")
            }
        }
        if let expectedPreviewType {
            guard set.attributes?.previewType == expectedPreviewType else {
                throw MediaArgumentError("Apple returned an app preview set with an unexpected preview type")
            }
        }
    }

    private func validatePreviewSets(
        _ sets: [ASCPreviewSet],
        expectedPreviewType: String?,
        allowedPreviewTypes: Set<String>? = nil,
        expectedParent: MediaSetParent? = nil
    ) throws {
        var identities = Set<String>()
        for set in sets {
            try validatePreviewSet(
                set,
                expectedID: nil,
                expectedPreviewType: expectedPreviewType,
                expectedParent: expectedParent
            )
            if let allowedPreviewTypes {
                guard let previewType = set.attributes?.previewType,
                      allowedPreviewTypes.contains(previewType) else {
                    throw MediaArgumentError("Apple returned an app preview set outside the requested preview_types filter")
                }
            }
            guard identities.insert(set.id).inserted else {
                throw MediaArgumentError("Apple returned duplicate app-preview-set identities")
            }
        }
    }

    private func validateScreenshotResource(
        _ screenshot: ASCScreenshot,
        expectedID: String?,
        expectedSetID: String? = nil
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: screenshot.type,
            id: screenshot.id,
            expectedType: "appScreenshots",
            expectedID: expectedID,
            context: "screenshot"
        )
        try validateMediaResourceSelf(
            screenshot.links?.`self`,
            kind: .screenshot,
            id: screenshot.id,
            context: "screenshot"
        )
        try validateChildLineage(
            screenshot.relationships?.appScreenshotSet,
            expectedType: "appScreenshotSets",
            expectedID: expectedSetID,
            context: "screenshot appScreenshotSet lineage"
        )
    }

    private func validateScreenshotResources(
        _ screenshots: [ASCScreenshot],
        expectedSetID: String? = nil
    ) throws {
        var identities = Set<String>()
        for screenshot in screenshots {
            try validateScreenshotResource(
                screenshot,
                expectedID: nil,
                expectedSetID: expectedSetID
            )
            guard identities.insert(screenshot.id).inserted else {
                throw MediaArgumentError("Apple returned duplicate screenshot identities")
            }
        }
    }

    private func validatePreviewResource(
        _ preview: ASCPreview,
        expectedID: String?,
        expectedSetID: String? = nil
    ) throws {
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: preview.type,
            id: preview.id,
            expectedType: "appPreviews",
            expectedID: expectedID,
            context: "app preview"
        )
        try validateMediaResourceSelf(
            preview.links?.`self`,
            kind: .preview,
            id: preview.id,
            context: "app preview"
        )
        try validateChildLineage(
            preview.relationships?.appPreviewSet,
            expectedType: "appPreviewSets",
            expectedID: expectedSetID,
            context: "app preview appPreviewSet lineage"
        )
    }

    private func validatePreviewResources(
        _ previews: [ASCPreview],
        expectedSetID: String? = nil
    ) throws {
        var identities = Set<String>()
        for preview in previews {
            try validatePreviewResource(
                preview,
                expectedID: nil,
                expectedSetID: expectedSetID
            )
            guard identities.insert(preview.id).inserted else {
                throw MediaArgumentError("Apple returned duplicate app preview identities")
            }
        }
    }

    private func validateMediaSetLineage(
        appStoreVersion: ASCRelationship?,
        customProductPage: ASCRelationship?,
        treatment: ASCRelationship?,
        expectedParent: MediaSetParent?,
        context: String
    ) throws {
        var parents: [MediaSetParent] = []
        try appendMediaSetLineage(
            appStoreVersion,
            expectedType: "appStoreVersionLocalizations",
            context: "\(context) appStoreVersionLocalization",
            to: &parents,
            makeParent: MediaSetParent.appStoreVersion
        )
        try appendMediaSetLineage(
            customProductPage,
            expectedType: "appCustomProductPageLocalizations",
            context: "\(context) appCustomProductPageLocalization",
            to: &parents,
            makeParent: MediaSetParent.customProductPage
        )
        try appendMediaSetLineage(
            treatment,
            expectedType: "appStoreVersionExperimentTreatmentLocalizations",
            context: "\(context) appStoreVersionExperimentTreatmentLocalization",
            to: &parents,
            makeParent: MediaSetParent.treatment
        )
        guard parents.count <= 1 else {
            throw MediaArgumentError("Apple returned \(context) with conflicting localization-parent lineage")
        }
        if let expectedParent, let returnedParent = parents.first {
            guard returnedParent.resourceType == expectedParent.resourceType,
                  returnedParent.id == expectedParent.id else {
                throw MediaArgumentError("Apple returned \(context) outside the requested localization parent")
            }
        }
    }

    private func appendMediaSetLineage(
        _ relationship: ASCRelationship?,
        expectedType: String,
        context: String,
        to parents: inout [MediaSetParent],
        makeParent: (String) -> MediaSetParent
    ) throws {
        guard let linkage = relationship?.data else { return }
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: linkage.type,
            id: linkage.id,
            expectedType: expectedType,
            context: context
        )
        parents.append(makeParent(linkage.id))
    }

    private func validateChildLineage(
        _ relationship: ASCRelationship?,
        expectedType: String,
        expectedID: String?,
        context: String
    ) throws {
        guard let linkage = relationship?.data else { return }
        try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
            type: linkage.type,
            id: linkage.id,
            expectedType: expectedType,
            expectedID: expectedID,
            context: context
        )
    }

    private func validateMediaResourceSelf(
        _ value: String?,
        kind: MediaResourceKind,
        id: String,
        context: String
    ) throws {
        guard let value else { return }
        try validateMediaDocumentSelf(
            value,
            expectedPath: mediaResourcePath(kind: kind, id: id),
            context: "\(context) resource",
            allowQuery: false
        )
    }

    private func validateMediaDocumentSelf(
        _ value: String,
        expectedPath: String,
        context: String,
        allowQuery: Bool = true
    ) throws {
        do {
            _ = try httpClient.validatedScopedLink(
                value,
                scope: PaginationScope(
                    path: expectedPath,
                    allowedParameters: allowQuery ? nil : []
                )
            )
        } catch {
            throw MediaArgumentError(
                "Apple returned an invalid or out-of-origin required links.self in \(context): \(Redactor.redact(error.localizedDescription))"
            )
        }
    }

    private func mediaContinuationCursor(
        _ value: String,
        path: String,
        query: [String: String],
        context: String
    ) throws -> String {
        do {
            let request = try httpClient.validatedScopedLink(
                value,
                scope: mediaPaginationScope(path: path, query: query)
            )
            guard let cursor = request.parameters["cursor"],
                  !cursor.isEmpty,
                  cursor == cursor.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw MediaArgumentError("The continuation cursor is empty or non-canonical")
            }
            return cursor
        } catch {
            throw MediaArgumentError(
                "Apple returned an invalid or out-of-origin continuation in \(context): \(Redactor.redact(error.localizedDescription))"
            )
        }
    }

    private func validateMediaCollectionPage(
        links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation?,
        dataCount: Int,
        expectedPath: String,
        query: [String: String],
        requestedCursor: String?,
        requireTotal: Bool,
        context: String
    ) throws -> MediaCollectionPageValidation {
        guard let requestedLimitText = query["limit"],
              let requestedLimit = Int(requestedLimitText),
              requestedLimit > 0,
              dataCount <= requestedLimit else {
            throw MediaArgumentError("Apple returned more resources than the requested limit in \(context)")
        }

        let selfScope = PaginationScope(
            path: expectedPath,
            requiredParameters: query,
            allowedParameters: Set(query.keys).union(["cursor"])
        )
        let selfRequest: PaginationRequest
        do {
            selfRequest = try httpClient.validatedScopedLink(links.`self`, scope: selfScope)
        } catch {
            throw MediaArgumentError(
                "Apple returned an invalid or out-of-origin required links.self in \(context): \(Redactor.redact(error.localizedDescription))"
            )
        }
        guard selfRequest.parameters["cursor"] == requestedCursor else {
            throw MediaArgumentError("Apple returned links.self for a different page cursor in \(context)")
        }

        if let first = links.first {
            let firstRequest: PaginationRequest
            do {
                firstRequest = try httpClient.validatedScopedLink(first, scope: selfScope)
            } catch {
                throw MediaArgumentError(
                    "Apple returned an invalid or out-of-origin links.first in \(context): \(Redactor.redact(error.localizedDescription))"
                )
            }
            guard firstRequest.parameters["cursor"] == nil else {
                throw MediaArgumentError("Apple returned links.first with a continuation cursor in \(context)")
            }
        }

        let nextCursor: String?
        if let next = links.next {
            let cursor = try mediaContinuationCursor(
                next,
                path: expectedPath,
                query: query,
                context: "\(context) links.next"
            )
            guard cursor != requestedCursor else {
                throw MediaArgumentError("Apple returned a non-advancing continuation cursor in \(context)")
            }
            nextCursor = cursor
        } else {
            nextCursor = nil
        }

        guard let meta else {
            guard !requireTotal else {
                throw MediaArgumentError("Apple omitted required paging metadata in \(context)")
            }
            return MediaCollectionPageValidation(
                total: nil,
                nextURL: links.next,
                nextCursor: nextCursor
            )
        }
        guard let paging = meta.paging,
              let pageLimit = paging.limit,
              pageLimit == requestedLimit,
              dataCount <= pageLimit else {
            throw MediaArgumentError("Apple returned a paging limit outside the requested scope in \(context)")
        }

        if let cursor = paging.nextCursor {
            guard !cursor.isEmpty,
                  cursor == cursor.trimmingCharacters(in: .whitespacesAndNewlines),
                  cursor == nextCursor else {
                throw MediaArgumentError("Apple returned an empty or non-canonical paging.nextCursor in \(context)")
            }
        }
        if requireTotal, paging.nextCursor != nextCursor {
            throw MediaArgumentError("Apple returned paging.nextCursor inconsistent with links.next in \(context)")
        }

        if let total = paging.total {
            guard total >= 0, total >= dataCount else {
                throw MediaArgumentError("Apple returned an impossible paging total in \(context)")
            }
        } else if requireTotal {
            throw MediaArgumentError("Apple omitted paging.total required to prove complete inventory in \(context)")
        }

        return MediaCollectionPageValidation(
            total: paging.total,
            nextURL: links.next,
            nextCursor: nextCursor
        )
    }

    private func mediaResourcePath(kind: MediaResourceKind, id: String) throws -> String {
        switch kind {
        case .screenshotSet:
            return "/v1/appScreenshotSets/\(try ASCPathSegment.encode(id, field: "media resource ID"))"
        case .previewSet:
            return "/v1/appPreviewSets/\(try ASCPathSegment.encode(id, field: "media resource ID"))"
        case .screenshot:
            return "/v1/appScreenshots/\(try ASCPathSegment.encode(id, field: "media resource ID"))"
        case .preview:
            return "/v1/appPreviews/\(try ASCPathSegment.encode(id, field: "media resource ID"))"
        }
    }

    private func fetchScreenshotSet(_ setID: String) async throws -> ASCScreenshotSet {
        let endpoint = try mediaResourcePath(kind: .screenshotSet, id: setID)
        let data = try await httpClient.get(endpoint)
        let response = try JSONDecoder().decode(ASCScreenshotSetResponse.self, from: data)
        try validateScreenshotSet(response.data, expectedID: setID, expectedDisplayType: nil)
        try validateMediaDocumentSelf(
            response.links.`self`,
            expectedPath: endpoint,
            context: "screenshot-set get response",
            allowQuery: false
        )
        return response.data
    }

    private func fetchPreviewSet(_ setID: String) async throws -> ASCPreviewSet {
        let endpoint = try mediaResourcePath(kind: .previewSet, id: setID)
        let data = try await httpClient.get(endpoint)
        let response = try JSONDecoder().decode(ASCPreviewSetResponse.self, from: data)
        try validatePreviewSet(response.data, expectedID: setID, expectedPreviewType: nil)
        try validateMediaDocumentSelf(
            response.links.`self`,
            expectedPath: endpoint,
            context: "app-preview-set get response",
            allowQuery: false
        )
        return response.data
    }

    private func fetchAllScreenshotSets(
        parent: MediaSetParent,
        displayType: String
    ) async throws -> [ASCScreenshotSet] {
        let endpoint = try mediaSetCollectionEndpoint(parent: parent, kind: .screenshot)
        let query = [
            "filter[screenshotDisplayType]": displayType,
            "limit": "200"
        ]
        var response = try await httpClient.get(
            endpoint,
            parameters: query,
            as: ASCScreenshotSetsResponse.self
        )
        var sets: [ASCScreenshotSet] = []
        var identities = Set<String>()
        var continuationCursors = Set<String>()
        var requestedCursor: String?
        var stableTotal: Int?
        var pageCount = 0
        while true {
            pageCount += 1
            guard pageCount <= 1_000 else {
                throw MediaArgumentError("Screenshot-set pagination exceeded the safety limit")
            }
            let page = try validateMediaCollectionPage(
                links: response.links,
                meta: response.meta,
                dataCount: response.data.count,
                expectedPath: endpoint,
                query: query,
                requestedCursor: requestedCursor,
                requireTotal: true,
                context: "screenshot-set pagination"
            )
            if let total = page.total {
                if let stableTotal, stableTotal != total {
                    throw MediaArgumentError("Apple changed paging.total during screenshot-set pagination")
                }
                stableTotal = total
            }
            try validateScreenshotSets(
                response.data,
                expectedDisplayType: displayType,
                expectedParent: parent
            )
            for set in response.data {
                guard identities.insert(set.id).inserted else {
                    throw MediaArgumentError("Apple returned a duplicate screenshot set across pages")
                }
                sets.append(set)
            }
            guard let total = stableTotal, sets.count <= total else {
                throw MediaArgumentError("Apple returned more screenshot sets than paging.total")
            }
            guard let next = page.nextURL else {
                guard sets.count == total else {
                    throw MediaArgumentError("Apple ended screenshot-set pagination before the declared total")
                }
                return sets
            }
            guard let nextCursor = page.nextCursor,
                  continuationCursors.insert(nextCursor).inserted else {
                throw MediaArgumentError("Apple returned a repeated screenshot-set continuation cursor")
            }
            requestedCursor = nextCursor
            response = try await httpClient.getPage(
                next,
                scope: mediaPaginationScope(path: endpoint, query: query),
                as: ASCScreenshotSetsResponse.self
            )
        }
    }

    private func fetchAllPreviewSets(
        parent: MediaSetParent,
        previewType: String
    ) async throws -> [ASCPreviewSet] {
        let endpoint = try mediaSetCollectionEndpoint(parent: parent, kind: .preview)
        let query = [
            "filter[previewType]": previewType,
            "limit": "200"
        ]
        var response = try await httpClient.get(
            endpoint,
            parameters: query,
            as: ASCPreviewSetsResponse.self
        )
        var sets: [ASCPreviewSet] = []
        var identities = Set<String>()
        var continuationCursors = Set<String>()
        var requestedCursor: String?
        var stableTotal: Int?
        var pageCount = 0
        while true {
            pageCount += 1
            guard pageCount <= 1_000 else {
                throw MediaArgumentError("App-preview-set pagination exceeded the safety limit")
            }
            let page = try validateMediaCollectionPage(
                links: response.links,
                meta: response.meta,
                dataCount: response.data.count,
                expectedPath: endpoint,
                query: query,
                requestedCursor: requestedCursor,
                requireTotal: true,
                context: "app-preview-set pagination"
            )
            if let total = page.total {
                if let stableTotal, stableTotal != total {
                    throw MediaArgumentError("Apple changed paging.total during app-preview-set pagination")
                }
                stableTotal = total
            }
            try validatePreviewSets(
                response.data,
                expectedPreviewType: previewType,
                expectedParent: parent
            )
            for set in response.data {
                guard identities.insert(set.id).inserted else {
                    throw MediaArgumentError("Apple returned a duplicate app preview set across pages")
                }
                sets.append(set)
            }
            guard let total = stableTotal, sets.count <= total else {
                throw MediaArgumentError("Apple returned more app preview sets than paging.total")
            }
            guard let next = page.nextURL else {
                guard sets.count == total else {
                    throw MediaArgumentError("Apple ended app-preview-set pagination before the declared total")
                }
                return sets
            }
            guard let nextCursor = page.nextCursor,
                  continuationCursors.insert(nextCursor).inserted else {
                throw MediaArgumentError("Apple returned a repeated app-preview-set continuation cursor")
            }
            requestedCursor = nextCursor
            response = try await httpClient.getPage(
                next,
                scope: mediaPaginationScope(path: endpoint, query: query),
                as: ASCPreviewSetsResponse.self
            )
        }
    }

    private func fetchAllScreenshotIDs(setID: String) async throws -> [String] {
        let endpoint = "/v1/appScreenshotSets/\(try ASCPathSegment.encode(setID, field: "set_id"))/appScreenshots"
        let query = ["limit": "200"]
        var response = try await httpClient.get(endpoint, parameters: query, as: ASCScreenshotsResponse.self)
        var ids: [String] = []
        var identities = Set<String>()
        var continuationCursors = Set<String>()
        var requestedCursor: String?
        var stableTotal: Int?
        var pageCount = 0
        while true {
            pageCount += 1
            guard pageCount <= 1_000 else {
                throw MediaArgumentError("Screenshot membership pagination exceeded the safety limit")
            }
            let page = try validateMediaCollectionPage(
                links: response.links,
                meta: response.meta,
                dataCount: response.data.count,
                expectedPath: endpoint,
                query: query,
                requestedCursor: requestedCursor,
                requireTotal: true,
                context: "screenshot membership pagination"
            )
            if let total = page.total {
                if let stableTotal, stableTotal != total {
                    throw MediaArgumentError("Apple changed paging.total during screenshot membership pagination")
                }
                stableTotal = total
            }
            for screenshot in response.data {
                try validateScreenshotResource(
                    screenshot,
                    expectedID: nil,
                    expectedSetID: setID
                )
                guard identities.insert(screenshot.id).inserted else {
                    throw MediaArgumentError("Apple returned a duplicate screenshot identity across membership pages")
                }
                ids.append(screenshot.id)
            }
            guard let total = stableTotal, ids.count <= total else {
                throw MediaArgumentError("Apple returned more screenshot identities than paging.total")
            }
            guard let next = page.nextURL else {
                guard ids.count == total else {
                    throw MediaArgumentError("Apple ended screenshot membership pagination before the declared total")
                }
                return ids
            }
            guard let nextCursor = page.nextCursor,
                  continuationCursors.insert(nextCursor).inserted else {
                throw MediaArgumentError("Apple returned a repeated screenshot-membership continuation cursor")
            }
            requestedCursor = nextCursor
            response = try await httpClient.getPage(
                next,
                scope: mediaPaginationScope(path: endpoint, query: query),
                as: ASCScreenshotsResponse.self
            )
        }
    }

    private func fetchAllPreviewIDs(setID: String) async throws -> [String] {
        let endpoint = "/v1/appPreviewSets/\(try ASCPathSegment.encode(setID, field: "set_id"))/appPreviews"
        let query = ["limit": "200"]
        var response = try await httpClient.get(endpoint, parameters: query, as: ASCPreviewsResponse.self)
        var ids: [String] = []
        var identities = Set<String>()
        var continuationCursors = Set<String>()
        var requestedCursor: String?
        var stableTotal: Int?
        var pageCount = 0
        while true {
            pageCount += 1
            guard pageCount <= 1_000 else {
                throw MediaArgumentError("App preview membership pagination exceeded the safety limit")
            }
            let page = try validateMediaCollectionPage(
                links: response.links,
                meta: response.meta,
                dataCount: response.data.count,
                expectedPath: endpoint,
                query: query,
                requestedCursor: requestedCursor,
                requireTotal: true,
                context: "app preview membership pagination"
            )
            if let total = page.total {
                if let stableTotal, stableTotal != total {
                    throw MediaArgumentError("Apple changed paging.total during app preview membership pagination")
                }
                stableTotal = total
            }
            for preview in response.data {
                try validatePreviewResource(
                    preview,
                    expectedID: nil,
                    expectedSetID: setID
                )
                guard identities.insert(preview.id).inserted else {
                    throw MediaArgumentError("Apple returned a duplicate app preview identity across membership pages")
                }
                ids.append(preview.id)
            }
            guard let total = stableTotal, ids.count <= total else {
                throw MediaArgumentError("Apple returned more app preview identities than paging.total")
            }
            guard let next = page.nextURL else {
                guard ids.count == total else {
                    throw MediaArgumentError("Apple ended app-preview membership pagination before the declared total")
                }
                return ids
            }
            guard let nextCursor = page.nextCursor,
                  continuationCursors.insert(nextCursor).inserted else {
                throw MediaArgumentError("Apple returned a repeated app-preview-membership continuation cursor")
            }
            requestedCursor = nextCursor
            response = try await httpClient.getPage(
                next,
                scope: mediaPaginationScope(path: endpoint, query: query),
                as: ASCPreviewsResponse.self
            )
        }
    }

    private func validateCompleteMembership(
        _ requestedIDs: [String],
        currentIDs: [String],
        resourceName: String
    ) throws {
        guard requestedIDs.count == currentIDs.count,
              Set(requestedIDs) == Set(currentIDs) else {
            let requested = Set(requestedIDs)
            let current = Set(currentIDs)
            let missing = current.subtracting(requested).sorted()
            let foreign = requested.subtracting(current).sorted()
            throw MediaArgumentError(
                "The requested \(resourceName) array must contain the complete current membership exactly once; missing=\(missing), foreign=\(foreign)"
            )
        }
    }

    private func mediaExistingSetFailure(
        kind: MediaSetKind,
        parent: MediaSetParent,
        mediaType: String,
        candidates: [[String: Any]]
    ) -> CallTool.Result {
        MCPResult.jsonObject([
            "success": false,
            "operation": "create",
            "operationCommitState": "not_attempted",
            "mutationAttempted": false,
            "operationCommitted": false,
            "retrySafe": true,
            "parent": mediaParentProjection(parent),
            "mediaType": mediaType,
            "existingCandidates": candidates,
            "error": "The selected parent already has a matching media set"
        ], isError: true)
    }

    private func mediaPreRequestFailure(
        operation: String,
        kind: MediaSetKind,
        parent: MediaSetParent?,
        setID: String?,
        mediaType: String?,
        error: Error
    ) -> CallTool.Result {
        var payload: [String: Any] = [
            "success": false,
            "operation": operation,
            "operationCommitState": "not_attempted",
            "mutationAttempted": false,
            "operationCommitted": false,
            "retrySafe": true,
            "error": Redactor.redact(error.localizedDescription)
        ]
        if let parent { payload["parent"] = mediaParentProjection(parent) }
        if let setID { payload["setId"] = setID }
        if let mediaType { payload["mediaType"] = mediaType }
        return MCPResult.jsonObject(payload, isError: true)
    }

    private func mediaCreateRequestFailure(
        kind: MediaSetKind,
        parent: MediaSetParent,
        mediaType: String,
        error: Error
    ) async -> CallTool.Result {
        let disposition = ASCNonIdempotentWriteRecovery.failureDisposition(for: error, phase: .request)
        let diagnostic = await diagnosticMediaSets(kind: kind, parent: parent, mediaType: mediaType)
        return mediaCreateMutationFailure(
            kind: kind,
            parent: parent,
            setID: nil,
            responseSetID: nil,
            mediaType: mediaType,
            disposition: disposition,
            error: error,
            diagnostic: diagnostic
        )
    }

    private func mediaCreateAcceptedResponseFailure(
        kind: MediaSetKind,
        parent: MediaSetParent,
        setID: String?,
        responseSetID: String?,
        mediaType: String,
        error: Error
    ) async -> CallTool.Result {
        let diagnostic = await diagnosticMediaSets(kind: kind, parent: parent, mediaType: mediaType)
        return mediaCreateMutationFailure(
            kind: kind,
            parent: parent,
            setID: setID,
            responseSetID: responseSetID,
            mediaType: mediaType,
            disposition: .committedUnverified,
            error: error,
            diagnostic: diagnostic
        )
    }

    private func diagnosticMediaSets(
        kind: MediaSetKind,
        parent: MediaSetParent,
        mediaType: String
    ) async -> ([[String: Any]], String?) {
        do {
            switch kind {
            case .screenshot:
                return (try await fetchAllScreenshotSets(parent: parent, displayType: mediaType).map(formatScreenshotSet), nil)
            case .preview:
                return (try await fetchAllPreviewSets(parent: parent, previewType: mediaType).map(formatPreviewSet), nil)
            }
        } catch {
            return ([], Redactor.redact(error.localizedDescription))
        }
    }

    private func mediaCreateMutationFailure(
        kind: MediaSetKind,
        parent: MediaSetParent,
        setID: String?,
        responseSetID: String?,
        mediaType: String,
        disposition: ASCNonIdempotentWriteFailureDisposition,
        error: Error,
        diagnostic: ([[String: Any]], String?)
    ) -> CallTool.Result {
        var payload: [String: Any] = [
            "success": false,
            "operation": "create",
            "operationCommitState": disposition.rawValue,
            "write_outcome": disposition.rawValue,
            "mutationAttempted": true,
            "retrySafe": disposition == .rejected,
            "parent": mediaParentProjection(parent),
            "mediaType": mediaType,
            "error": Redactor.redact(error.localizedDescription),
            "inspection": mediaParentInspection(kind: kind, parent: parent, mediaType: mediaType)
        ]
        if let setID { payload["setId"] = setID }
        if let responseSetID { payload["responseSetId"] = responseSetID }
        if !diagnostic.0.isEmpty {
            payload["observedCandidates"] = diagnostic.0
            payload["candidateAttributionConfirmed"] = false
            payload["createdByInvocation"] = false
        }
        if let diagnosticError = diagnostic.1 { payload["inspectionError"] = diagnosticError }
        switch disposition {
        case .rejected:
            payload["operationCommitted"] = false
            payload["outcomeUnknown"] = false
        case .outcomeUnknown:
            payload["operationCommitted"] = NSNull()
            payload["outcomeUnknown"] = true
            payload["inspectionRequired"] = true
        case .committedUnverified:
            payload["operationCommitted"] = true
            payload["outcomeUnknown"] = false
            payload["inspectionRequired"] = true
        }
        return MCPResult.jsonObject(payload, isError: true)
    }

    private func mediaRequestMutationFailure(
        operation: String,
        kind: MediaSetKind,
        setID: String,
        error: Error
    ) -> CallTool.Result {
        mediaMutationFailure(
            operation: operation,
            kind: kind,
            setID: setID,
            disposition: ASCNonIdempotentWriteRecovery.failureDisposition(for: error, phase: .request),
            error: error
        )
    }

    private func mediaAcceptedMutationFailure(
        operation: String,
        kind: MediaSetKind,
        setID: String,
        error: Error
    ) -> CallTool.Result {
        mediaMutationFailure(
            operation: operation,
            kind: kind,
            setID: setID,
            disposition: .committedUnverified,
            error: error
        )
    }

    private func mediaRequestChildDeleteFailure(
        kind: MediaSetKind,
        resourceID: String,
        error: Error
    ) -> CallTool.Result {
        mediaChildDeleteFailure(
            kind: kind,
            resourceID: resourceID,
            disposition: ASCNonIdempotentWriteRecovery.failureDisposition(for: error, phase: .request),
            error: error
        )
    }

    private func mediaAcceptedChildDeleteFailure(
        kind: MediaSetKind,
        resourceID: String,
        error: Error
    ) -> CallTool.Result {
        mediaChildDeleteFailure(
            kind: kind,
            resourceID: resourceID,
            disposition: .committedUnverified,
            error: error
        )
    }

    private func mediaChildDeleteFailure(
        kind: MediaSetKind,
        resourceID: String,
        disposition: ASCNonIdempotentWriteFailureDisposition,
        error: Error
    ) -> CallTool.Result {
        var payload: [String: Any] = [
            "success": false,
            "operation": "delete",
            "operationCommitState": disposition.rawValue,
            "write_outcome": disposition.rawValue,
            "mutationAttempted": true,
            "retrySafe": disposition == .rejected,
            "resourceId": resourceID,
            "error": Redactor.redact(error.localizedDescription),
            "inspection": [
                "tool": kind.getChildTool,
                "arguments": [kind.childIDArgument: resourceID],
                "instruction": "Inspect the exact resource before another delete attempt."
            ]
        ]
        switch disposition {
        case .rejected:
            payload["operationCommitted"] = false
            payload["outcomeUnknown"] = false
        case .outcomeUnknown:
            payload["operationCommitted"] = NSNull()
            payload["outcomeUnknown"] = true
            payload["inspectionRequired"] = true
        case .committedUnverified:
            payload["operationCommitted"] = true
            payload["outcomeUnknown"] = false
            payload["inspectionRequired"] = true
        }
        return MCPResult.jsonObject(payload, isError: true)
    }

    private func mediaMutationFailure(
        operation: String,
        kind: MediaSetKind,
        setID: String,
        disposition: ASCNonIdempotentWriteFailureDisposition,
        error: Error
    ) -> CallTool.Result {
        var payload: [String: Any] = [
            "success": false,
            "operation": operation,
            "operationCommitState": disposition.rawValue,
            "write_outcome": disposition.rawValue,
            "mutationAttempted": true,
            "retrySafe": disposition == .rejected,
            "setId": setID,
            "error": Redactor.redact(error.localizedDescription),
            "inspection": mediaSetInspection(kind: kind, setID: setID)
        ]
        switch disposition {
        case .rejected:
            payload["operationCommitted"] = false
            payload["outcomeUnknown"] = false
        case .outcomeUnknown:
            payload["operationCommitted"] = NSNull()
            payload["outcomeUnknown"] = true
            payload["inspectionRequired"] = true
        case .committedUnverified:
            payload["operationCommitted"] = true
            payload["outcomeUnknown"] = false
            payload["inspectionRequired"] = true
        }
        return MCPResult.jsonObject(payload, isError: true)
    }

    private func mediaParentInspection(
        kind: MediaSetKind,
        parent: MediaSetParent,
        mediaType: String
    ) -> [String: Any] {
        [
            "tool": kind.listTool,
            "arguments": [
                parent.canonicalArgumentName: parent.id,
                kind.mediaFilterArgument: [mediaType],
                "limit": 200
            ],
            "continueWithNextUrl": true,
            "instruction": "Inspect the complete matching parent-scoped set collection before any retry."
        ]
    }

    private func mediaSetInspection(kind: MediaSetKind, setID: String) -> [String: Any] {
        [
            "getSet": [
                "tool": kind.getTool,
                "arguments": ["set_id": setID]
            ],
            "listChildren": [
                "tool": kind.listChildrenTool,
                "arguments": ["set_id": setID, "limit": 200],
                "continueWithNextUrl": true
            ],
            "instruction": "Inspect the exact set and its complete ordered membership before another mutation."
        ]
    }

    private func mediaPaginationScope(path: String, query: [String: String]) -> PaginationScope {
        PaginationScope(
            path: path,
            requiredParameters: query,
            allowedParameters: Set(query.keys).union(["cursor"]),
            requiredNonEmptyParameters: ["cursor"]
        )
    }

    private func nullableNonemptyString(
        _ value: Value?,
        fieldName: String
    ) throws -> NullableAttributeValue? {
        guard let value else {
            return nil
        }
        if value.isNull {
            return .null
        }
        guard let string = value.stringValue,
              !string.isEmpty,
              string == string.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ASCError.parsing("'\(fieldName)' must be a non-empty string without surrounding whitespace or null")
        }
        return .string(string)
    }

    private func nullablePreviewMimeType(_ value: Value?) throws -> NullableAttributeValue? {
        guard let value else {
            return .string("video/mp4")
        }
        if value.isNull {
            return .null
        }
        guard let string = value.stringValue,
              !string.isEmpty,
              string == string.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ASCError.parsing("'mime_type' must be a non-empty string without surrounding whitespace or null")
        }
        return .string(string)
    }
}

private final class MediaUploadSemanticValidationState: Sendable {
    private struct State: Sendable {
        var expectedResourceID: String?
        var firstFailure: String?
    }

    private let resourceName: String
    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    init(resourceName: String) {
        self.resourceName = resourceName
    }

    func expectedResourceID() -> String? {
        state.withLock { $0.expectedResourceID }
    }

    func establishResourceID(_ resourceID: String) {
        state.withLock { current in
            if current.expectedResourceID == nil {
                current.expectedResourceID = resourceID
            }
        }
    }

    func record(_ error: Error) {
        let message = Redactor.redact(error.localizedDescription)
        state.withLock { current in
            if current.firstFailure == nil {
                current.firstFailure = message
            }
        }
    }

    func enforcing<Resource: RecoverableUploadResource>(
        _ outcome: UploadTransactionOutcome<Resource>
    ) -> UploadTransactionOutcome<Resource> {
        guard let failure = state.withLock({ $0.firstFailure }) else {
            return outcome
        }
        let message = "A confirmed \(resourceName) response violated immutable identity, lineage, or document-link scope: \(failure) Later reconciliation cannot override that semantic conflict."
        switch outcome {
        case .success(let resource, _),
             .processingPending(_, let resource, _):
            return .commitUnresolved(message, resource)
        default:
            return outcome
        }
    }
}
