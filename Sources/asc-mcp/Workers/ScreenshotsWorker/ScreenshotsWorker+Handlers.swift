import Foundation
import MCP

// MARK: - Tool Handlers
extension ScreenshotsWorker {

    /// Lists screenshot sets for a version localization
    /// - Returns: JSON array of screenshot sets with display types
    func listScreenshotSets(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let locIdValue = arguments["localization_id"],
              let localizationId = locIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCScreenshotSetsResponse
            let endpoint = "/v1/appStoreVersionLocalizations/\(try ASCPathSegment.encode(localizationId))/appScreenshotSets"
            var queryParams: [String: String] = [:]

            if let limitValue = arguments["limit"],
               let limit = limitValue.intValue {
                queryParams["limit"] = String(min(max(limit, 1), 200))
            } else {
                queryParams["limit"] = "25"
            }
            try applyStringArrayFilter(
                arguments["display_types"],
                fieldName: "display_types",
                appleName: "filter[screenshotDisplayType]",
                allowedValues: Set(Self.screenshotDisplayTypes),
                to: &queryParams
            )
            try applyStringArrayFilter(
                arguments["custom_product_page_localization_ids"],
                fieldName: "custom_product_page_localization_ids",
                appleName: "filter[appCustomProductPageLocalization]",
                to: &queryParams
            )
            try applyStringArrayFilter(
                arguments["treatment_localization_ids"],
                fieldName: "treatment_localization_ids",
                appleName: "filter[appStoreVersionExperimentTreatmentLocalization]",
                to: &queryParams
            )

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: mediaPaginationScope(path: endpoint, query: queryParams),
                    as: ASCScreenshotSetsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCScreenshotSetsResponse.self
                )
            }

            let sets = response.data.map { formatScreenshotSet($0) }

            var result: [String: Any] = [
                "success": true,
                "screenshot_sets": sets,
                "count": sets.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list screenshot sets: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a screenshot set for a version localization
    /// - Returns: JSON with created screenshot set details
    func createScreenshotSet(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let displayTypeValue = arguments["display_type"],
              let displayType = displayTypeValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'display_type' is missing")],
                isError: true
            )
        }

        guard Set(Self.screenshotDisplayTypes).contains(displayType) else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Unsupported value for 'display_type': \(displayType)")],
                isError: true
            )
        }

        guard let parent = mediaSetParent(from: arguments) else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Provide exactly one localization parent: localization_id, app_store_version_localization_id, custom_product_page_localization_id, or treatment_localization_id")],
                isError: true
            )
        }

        do {
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

            let response: ASCScreenshotSetResponse = try await httpClient.post(
                "/v1/appScreenshotSets",
                body: request,
                as: ASCScreenshotSetResponse.self
            )

            let result = [
                "success": true,
                "screenshot_set": formatScreenshotSet(response.data)
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create screenshot set: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a screenshot set
    /// - Returns: JSON confirmation
    func deleteScreenshotSet(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let setIdValue = arguments["set_id"],
              let setId = setIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'set_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appScreenshotSets/\(try ASCPathSegment.encode(setId))")

            let result = [
                "success": true,
                "message": "Screenshot set '\(setId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to delete screenshot set: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists screenshots in a screenshot set
    /// - Returns: JSON array of screenshots with file info and upload status
    func listScreenshots(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let setIdValue = arguments["set_id"],
              let setId = setIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'set_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCScreenshotsResponse
            let endpoint = "/v1/appScreenshotSets/\(try ASCPathSegment.encode(setId))/appScreenshots"
            let limit = arguments["limit"]?.intValue ?? 25
            let queryParams = ["limit": String(min(max(limit, 1), 200))]

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: mediaPaginationScope(path: endpoint, query: queryParams),
                    as: ASCScreenshotsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCScreenshotsResponse.self
                )
            }

            let screenshots = response.data.map { formatScreenshot($0) }

            var result: [String: Any] = [
                "success": true,
                "screenshots": screenshots,
                "count": screenshots.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list screenshots: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Uploads a screenshot and reconciles its asynchronous processing state
    /// - Returns: JSON with terminal or accepted processing-pending screenshot info
    func uploadScreenshot(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let setId = arguments["set_id"]?.stringValue,
              let filePath = arguments["file_path"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: set_id, file_path")],
                isError: true
            )
        }

        let outcome: UploadTransactionOutcome<ASCScreenshot> = await UploadTransactionRecovery.perform(
            filePath: filePath,
            resourceName: "screenshot",
            expectedType: "appScreenshots",
            reservationEndpoint: "/v1/appScreenshots",
            httpClient: httpClient,
            uploadService: uploadService,
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
                                    data: ASCResourceIdentifier(type: "appScreenshotSets", id: setId)
                                )
                            )
                        )
                    )
                )
            },
            decodeResource: {
                try JSONDecoder().decode(ASCScreenshotResponse.self, from: $0).data
            },
            makeCommitBody: { screenshotId, checksum in
                try JSONEncoder().encode(
                    CommitScreenshotRequest(
                        data: CommitScreenshotRequest.CommitData(
                            id: screenshotId,
                            attributes: CommitScreenshotRequest.Attributes(
                                sourceFileChecksum: checksum,
                                uploaded: true
                            )
                        )
                    )
                )
            },
            resourceEndpoint: { "/v1/appScreenshots/\(try ASCPathSegment.encode($0))" }
        )

        return UploadTransactionRecovery.result(
            for: outcome,
            descriptor: UploadRecoveryDescriptor(
                resourceName: "screenshot",
                successKey: "screenshot",
                idArgument: "screenshot_id",
                getTool: "screenshots_get",
                getIDArgument: "screenshot_id",
                deleteTool: "screenshots_delete",
                inspectionTool: "screenshots_list",
                inspectionArguments: ["set_id": setId]
            ),
            format: formatScreenshot
        )
    }

    /// Uploads multiple screenshots to a set sequentially
    /// - Returns: JSON array with results for each file (success or error)
    func uploadScreenshotBatch(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let setId = arguments["set_id"]?.stringValue,
              let filePaths = arguments["file_paths"]?.arrayValue?.compactMap({ $0.stringValue }),
              !filePaths.isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: set_id, file_paths (non-empty array)")],
                isError: true
            )
        }

        var results: [[String: Any]] = []
        var successCount = 0
        var failCount = 0

        let descriptor = UploadRecoveryDescriptor(
            resourceName: "screenshot",
            successKey: "screenshot",
            idArgument: "screenshot_id",
            getTool: "screenshots_get",
            getIDArgument: "screenshot_id",
            deleteTool: "screenshots_delete",
            inspectionTool: "screenshots_list",
            inspectionArguments: ["set_id": setId]
        )

        for filePath in filePaths {
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            let outcome: UploadTransactionOutcome<ASCScreenshot> = await UploadTransactionRecovery.perform(
                filePath: filePath,
                resourceName: "screenshot",
                expectedType: "appScreenshots",
                reservationEndpoint: "/v1/appScreenshots",
                httpClient: httpClient,
                uploadService: uploadService,
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
                                        data: ASCResourceIdentifier(type: "appScreenshotSets", id: setId)
                                    )
                                )
                            )
                        )
                    )
                },
                decodeResource: {
                    try JSONDecoder().decode(ASCScreenshotResponse.self, from: $0).data
                },
                makeCommitBody: { screenshotId, checksum in
                    try JSONEncoder().encode(
                        CommitScreenshotRequest(
                            data: CommitScreenshotRequest.CommitData(
                                id: screenshotId,
                                attributes: CommitScreenshotRequest.Attributes(
                                    sourceFileChecksum: checksum,
                                    uploaded: true
                                )
                            )
                        )
                    )
                },
                resourceEndpoint: { "/v1/appScreenshots/\(try ASCPathSegment.encode($0))" }
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
        guard let arguments = params.arguments,
              let screenshotId = arguments["screenshot_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'screenshot_id' is missing")],
                isError: true
            )
        }

        do {
            let data = try await httpClient.get("/v1/appScreenshots/\(try ASCPathSegment.encode(screenshotId))")
            let response = try JSONDecoder().decode(ASCScreenshotResponse.self, from: data)

            let result = [
                "success": true,
                "screenshot": formatScreenshot(response.data)
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get screenshot: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a screenshot
    /// - Returns: JSON confirmation
    func deleteScreenshot(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let screenshotIdValue = arguments["screenshot_id"],
              let screenshotId = screenshotIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'screenshot_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appScreenshots/\(try ASCPathSegment.encode(screenshotId))")

            let result = [
                "success": true,
                "message": "Screenshot '\(screenshotId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to delete screenshot: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Reorders screenshots within a screenshot set
    /// - Returns: JSON confirmation
    func reorderScreenshots(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let setIdValue = arguments["set_id"],
              let setId = setIdValue.stringValue,
              let idsValue = arguments["screenshot_ids"],
              let idsString = idsValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: set_id, screenshot_ids")],
                isError: true
            )
        }

        do {
            let ids = idsString.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            let resourceIds = ids.map { ASCResourceIdentifier(type: "appScreenshots", id: $0) }
            let request = ReorderScreenshotsRequest(data: resourceIds)

            let encoder = JSONEncoder()
            let bodyData = try encoder.encode(request)
            _ = try await httpClient.patch(
                "/v1/appScreenshotSets/\(try ASCPathSegment.encode(setId))/relationships/appScreenshots",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Screenshots reordered in set '\(setId)'",
                "order": ids
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to reorder screenshots: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists app preview sets for a version localization
    /// - Returns: JSON array of preview sets with preview types
    func listPreviewSets(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let locIdValue = arguments["localization_id"],
              let localizationId = locIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPreviewSetsResponse
            let endpoint = "/v1/appStoreVersionLocalizations/\(try ASCPathSegment.encode(localizationId))/appPreviewSets"
            var queryParams: [String: String] = [:]

            if let limitValue = arguments["limit"],
               let limit = limitValue.intValue {
                queryParams["limit"] = String(min(max(limit, 1), 200))
            } else {
                queryParams["limit"] = "25"
            }
            try applyStringArrayFilter(
                arguments["preview_types"],
                fieldName: "preview_types",
                appleName: "filter[previewType]",
                allowedValues: Set(Self.previewTypes),
                to: &queryParams
            )
            try applyStringArrayFilter(
                arguments["custom_product_page_localization_ids"],
                fieldName: "custom_product_page_localization_ids",
                appleName: "filter[appCustomProductPageLocalization]",
                to: &queryParams
            )
            try applyStringArrayFilter(
                arguments["treatment_localization_ids"],
                fieldName: "treatment_localization_ids",
                appleName: "filter[appStoreVersionExperimentTreatmentLocalization]",
                to: &queryParams
            )

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: mediaPaginationScope(path: endpoint, query: queryParams),
                    as: ASCPreviewSetsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCPreviewSetsResponse.self
                )
            }

            let sets = response.data.map { formatPreviewSet($0) }

            var result: [String: Any] = [
                "success": true,
                "preview_sets": sets,
                "count": sets.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list preview sets: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates an app preview set for a version localization
    /// - Returns: JSON with created preview set details
    func createPreviewSet(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let previewTypeValue = arguments["preview_type"],
              let previewType = previewTypeValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'preview_type' is missing")],
                isError: true
            )
        }

        guard Set(Self.previewTypes).contains(previewType) else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Unsupported value for 'preview_type': \(previewType)")],
                isError: true
            )
        }

        guard let parent = mediaSetParent(from: arguments) else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Provide exactly one localization parent: localization_id, app_store_version_localization_id, custom_product_page_localization_id, or treatment_localization_id")],
                isError: true
            )
        }

        do {
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

            let response: ASCPreviewSetResponse = try await httpClient.post(
                "/v1/appPreviewSets",
                body: request,
                as: ASCPreviewSetResponse.self
            )

            let result = [
                "success": true,
                "preview_set": formatPreviewSet(response.data)
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create preview set: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes an app preview set
    /// - Returns: JSON confirmation
    func deletePreviewSet(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let setIdValue = arguments["set_id"],
              let setId = setIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'set_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appPreviewSets/\(try ASCPathSegment.encode(setId))")

            let result = [
                "success": true,
                "message": "Preview set '\(setId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to delete preview set: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Uploads an app preview and reconciles its asynchronous processing state
    /// - Returns: JSON with terminal or accepted processing-pending preview info
    func uploadPreview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let setId = arguments["set_id"]?.stringValue,
              let filePath = arguments["file_path"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: set_id, file_path")],
                isError: true
            )
        }

        let mimeType: NullableAttributeValue?
        let previewFrameTimeCode: NullableAttributeValue?
        do {
            mimeType = try nullablePreviewMimeType(arguments["mime_type"])
            previewFrameTimeCode = try nullableNonemptyString(
                arguments["preview_frame_time_code"],
                fieldName: "preview_frame_time_code"
            )
        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: \(error.localizedDescription)")],
                isError: true
            )
        }

        let outcome: UploadTransactionOutcome<ASCPreview> = await UploadTransactionRecovery.perform(
            filePath: filePath,
            resourceName: "app preview",
            expectedType: "appPreviews",
            reservationEndpoint: "/v1/appPreviews",
            httpClient: httpClient,
            uploadService: uploadService,
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
                                    data: ASCResourceIdentifier(type: "appPreviewSets", id: setId)
                                )
                            )
                        )
                    )
                )
            },
            decodeResource: {
                try JSONDecoder().decode(ASCPreviewResponse.self, from: $0).data
            },
            makeCommitBody: { previewId, checksum in
                try JSONEncoder().encode(
                    CommitPreviewRequest(
                        data: CommitPreviewRequest.CommitData(
                            id: previewId,
                            attributes: CommitPreviewRequest.Attributes(
                                sourceFileChecksum: checksum,
                                previewFrameTimeCode: previewFrameTimeCode,
                                uploaded: true
                            )
                        )
                    )
                )
            },
            resourceEndpoint: { "/v1/appPreviews/\(try ASCPathSegment.encode($0))" }
        )

        return UploadTransactionRecovery.result(
            for: outcome,
            descriptor: UploadRecoveryDescriptor(
                resourceName: "app preview",
                successKey: "preview",
                idArgument: "preview_id",
                getTool: "screenshots_get_preview",
                getIDArgument: "preview_id",
                deleteTool: "screenshots_delete_preview",
                inspectionTool: "screenshots_list_previews",
                inspectionArguments: ["set_id": setId]
            ),
            format: formatPreview
        )
    }

    /// Gets details of a specific app preview
    /// - Returns: JSON with preview details
    func getPreview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let previewId = arguments["preview_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'preview_id' is missing")],
                isError: true
            )
        }

        do {
            let data = try await httpClient.get("/v1/appPreviews/\(try ASCPathSegment.encode(previewId))")
            let response = try JSONDecoder().decode(ASCPreviewResponse.self, from: data)

            let result = [
                "success": true,
                "preview": formatPreview(response.data)
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get preview: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists app previews in a preview set
    /// - Returns: JSON array of previews with file info and upload status
    func listPreviews(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let setId = arguments["set_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'set_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPreviewsResponse
            let endpoint = "/v1/appPreviewSets/\(try ASCPathSegment.encode(setId))/appPreviews"
            let limit = arguments["limit"]?.intValue ?? 25
            let queryParams = ["limit": String(min(max(limit, 1), 200))]

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: mediaPaginationScope(path: endpoint, query: queryParams),
                    as: ASCPreviewsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCPreviewsResponse.self
                )
            }

            let previews = response.data.map { formatPreview($0) }

            var result: [String: Any] = [
                "success": true,
                "previews": previews,
                "count": previews.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list previews: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes an app preview
    /// - Returns: JSON confirmation
    func deletePreview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let previewIdValue = arguments["preview_id"],
              let previewId = previewIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'preview_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appPreviews/\(try ASCPathSegment.encode(previewId))")

            let result = [
                "success": true,
                "message": "Preview '\(previewId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to delete preview: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatScreenshotSet(_ set: ASCScreenshotSet) -> [String: Any] {
        return [
            "id": set.id,
            "type": set.type,
            "screenshotDisplayType": (set.attributes?.screenshotDisplayType).jsonSafe
        ]
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
                "errors": deliveryState.errors?.map { ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe] } ?? []
            ]
        }

        if let uploadOps = screenshot.attributes?.uploadOperations, !uploadOps.isEmpty {
            result["uploadOperationCount"] = uploadOps.count
            result["uploadOperations"] = formatUploadOperations(uploadOps)
        }

        return result
    }

    private func formatPreviewSet(_ set: ASCPreviewSet) -> [String: Any] {
        return [
            "id": set.id,
            "type": set.type,
            "previewType": (set.attributes?.previewType).jsonSafe
        ]
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
                "errors": deliveryState.errors?.map { ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe] } ?? []
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

        return result
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

    private enum MediaSetParent {
        case appStoreVersion(String)
        case customProductPage(String)
        case treatment(String)
    }

    private func mediaSetParent(from arguments: [String: Value]) -> MediaSetParent? {
        var parents: [MediaSetParent] = []
        if let id = arguments["localization_id"]?.stringValue {
            parents.append(.appStoreVersion(id))
        }
        if let id = arguments["app_store_version_localization_id"]?.stringValue {
            parents.append(.appStoreVersion(id))
        }
        if let id = arguments["custom_product_page_localization_id"]?.stringValue {
            parents.append(.customProductPage(id))
        }
        if let id = arguments["treatment_localization_id"]?.stringValue {
            parents.append(.treatment(id))
        }
        return parents.count == 1 ? parents[0] : nil
    }

    private func applyStringArrayFilter(
        _ value: Value?,
        fieldName: String,
        appleName: String,
        allowedValues: Set<String>? = nil,
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
        if let allowedValues {
            let unsupported = values.filter { !allowedValues.contains($0) }
            guard unsupported.isEmpty else {
                throw ASCError.parsing("Unsupported value(s) for '\(fieldName)': \(unsupported.joined(separator: ", "))")
            }
        }
        query[appleName] = values.joined(separator: ",")
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
