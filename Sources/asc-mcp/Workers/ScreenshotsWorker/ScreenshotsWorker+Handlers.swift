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
                content: [.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCScreenshotSetsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCScreenshotSetsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/appStoreVersionLocalizations/\(localizationId)/appScreenshotSets",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list screenshot sets: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a screenshot set for a version localization
    /// - Returns: JSON with created screenshot set details
    func createScreenshotSet(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let locIdValue = arguments["localization_id"],
              let localizationId = locIdValue.stringValue,
              let displayTypeValue = arguments["display_type"],
              let displayType = displayTypeValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: localization_id, display_type")],
                isError: true
            )
        }

        do {
            let request = CreateScreenshotSetRequest(
                data: CreateScreenshotSetRequest.CreateData(
                    attributes: CreateScreenshotSetRequest.Attributes(
                        screenshotDisplayType: displayType
                    ),
                    relationships: CreateScreenshotSetRequest.Relationships(
                        appStoreVersionLocalization: CreateScreenshotSetRequest.LocalizationRelationship(
                            data: ASCResourceIdentifier(type: "appStoreVersionLocalizations", id: localizationId)
                        )
                    )
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create screenshot set: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'set_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appScreenshotSets/\(setId)")

            let result = [
                "success": true,
                "message": "Screenshot set '\(setId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete screenshot set: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'set_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCScreenshotsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCScreenshotsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/appScreenshotSets/\(setId)/appScreenshots",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list screenshots: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a screenshot reservation for upload
    /// - Returns: JSON with screenshot details and upload operations
    func createScreenshot(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let setIdValue = arguments["set_id"],
              let setId = setIdValue.stringValue,
              let fileNameValue = arguments["file_name"],
              let fileName = fileNameValue.stringValue,
              let fileSizeValue = arguments["file_size"],
              let fileSize = fileSizeValue.intValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: set_id, file_name, file_size")],
                isError: true
            )
        }

        do {
            let request = CreateScreenshotRequest(
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

            let response: ASCScreenshotResponse = try await httpClient.post(
                "/v1/appScreenshots",
                body: request,
                as: ASCScreenshotResponse.self
            )

            let screenshot = formatScreenshot(response.data)

            let result = [
                "success": true,
                "screenshot": screenshot
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create screenshot: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'screenshot_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appScreenshots/\(screenshotId)")

            let result = [
                "success": true,
                "message": "Screenshot '\(screenshotId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete screenshot: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameters: set_id, screenshot_ids")],
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
                "/v1/appScreenshotSets/\(setId)/relationships/appScreenshots",
                body: bodyData
            )

            let result = [
                "success": true,
                "message": "Screenshots reordered in set '\(setId)'",
                "order": ids
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to reorder screenshots: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPreviewSetsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCPreviewSetsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/appStoreVersionLocalizations/\(localizationId)/appPreviewSets",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list preview sets: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates an app preview set for a version localization
    /// - Returns: JSON with created preview set details
    func createPreviewSet(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let locIdValue = arguments["localization_id"],
              let localizationId = locIdValue.stringValue,
              let previewTypeValue = arguments["preview_type"],
              let previewType = previewTypeValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: localization_id, preview_type")],
                isError: true
            )
        }

        do {
            let request = CreatePreviewSetRequest(
                data: CreatePreviewSetRequest.CreateData(
                    attributes: CreatePreviewSetRequest.Attributes(
                        previewType: previewType
                    ),
                    relationships: CreatePreviewSetRequest.Relationships(
                        appStoreVersionLocalization: CreatePreviewSetRequest.LocalizationRelationship(
                            data: ASCResourceIdentifier(type: "appStoreVersionLocalizations", id: localizationId)
                        )
                    )
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create preview set: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'set_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appPreviewSets/\(setId)")

            let result = [
                "success": true,
                "message": "Preview set '\(setId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete preview set: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates an app preview reservation for upload
    /// - Returns: JSON with preview details and upload operations
    func createPreview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let setIdValue = arguments["set_id"],
              let setId = setIdValue.stringValue,
              let fileNameValue = arguments["file_name"],
              let fileName = fileNameValue.stringValue,
              let fileSizeValue = arguments["file_size"],
              let fileSize = fileSizeValue.intValue,
              let mimeTypeValue = arguments["mime_type"],
              let mimeType = mimeTypeValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: set_id, file_name, file_size, mime_type")],
                isError: true
            )
        }

        do {
            let request = CreatePreviewRequest(
                data: CreatePreviewRequest.CreateData(
                    attributes: CreatePreviewRequest.Attributes(
                        fileName: fileName,
                        fileSize: fileSize,
                        mimeType: mimeType
                    ),
                    relationships: CreatePreviewRequest.Relationships(
                        appPreviewSet: CreatePreviewRequest.PreviewSetRelationship(
                            data: ASCResourceIdentifier(type: "appPreviewSets", id: setId)
                        )
                    )
                )
            )

            let response: ASCPreviewResponse = try await httpClient.post(
                "/v1/appPreviews",
                body: request,
                as: ASCPreviewResponse.self
            )

            let preview = formatPreview(response.data)

            let result = [
                "success": true,
                "preview": preview
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create preview: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'preview_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appPreviews/\(previewId)")

            let result = [
                "success": true,
                "message": "Preview '\(previewId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete preview: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatScreenshotSet(_ set: ASCScreenshotSet) -> [String: Any] {
        return [
            "id": set.id,
            "type": set.type,
            "screenshotDisplayType": set.attributes?.screenshotDisplayType.jsonSafe
        ]
    }

    private func formatScreenshot(_ screenshot: ASCScreenshot) -> [String: Any] {
        var result: [String: Any] = [
            "id": screenshot.id,
            "type": screenshot.type,
            "fileName": screenshot.attributes?.fileName.jsonSafe,
            "fileSize": screenshot.attributes?.fileSize.jsonSafe,
            "sourceFileChecksum": screenshot.attributes?.sourceFileChecksum.jsonSafe,
            "assetToken": screenshot.attributes?.assetToken.jsonSafe,
            "assetType": screenshot.attributes?.assetType.jsonSafe
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
            result["uploadOperations"] = uploadOps.map { op in
                [
                    "method": op.method.jsonSafe,
                    "url": op.url.jsonSafe,
                    "length": op.length.jsonSafe,
                    "offset": op.offset.jsonSafe
                ] as [String: Any]
            }
        }

        return result
    }

    private func formatPreviewSet(_ set: ASCPreviewSet) -> [String: Any] {
        return [
            "id": set.id,
            "type": set.type,
            "previewType": set.attributes?.previewType.jsonSafe
        ]
    }

    private func formatPreview(_ preview: ASCPreview) -> [String: Any] {
        var result: [String: Any] = [
            "id": preview.id,
            "type": preview.type,
            "fileName": preview.attributes?.fileName.jsonSafe,
            "fileSize": preview.attributes?.fileSize.jsonSafe,
            "sourceFileChecksum": preview.attributes?.sourceFileChecksum.jsonSafe,
            "mimeType": preview.attributes?.mimeType.jsonSafe,
            "videoUrl": preview.attributes?.videoUrl.jsonSafe,
            "previewFrameTimeCode": preview.attributes?.previewFrameTimeCode.jsonSafe
        ]

        if let previewImage = preview.attributes?.previewImage {
            result["previewImage"] = [
                "templateUrl": previewImage.templateUrl.jsonSafe,
                "width": previewImage.width.jsonSafe,
                "height": previewImage.height.jsonSafe
            ]
        }

        if let deliveryState = preview.attributes?.assetDeliveryState {
            result["assetDeliveryState"] = [
                "state": deliveryState.state.jsonSafe,
                "errors": deliveryState.errors?.map { ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe] } ?? []
            ]
        }

        if let uploadOps = preview.attributes?.uploadOperations, !uploadOps.isEmpty {
            result["uploadOperations"] = uploadOps.map { op in
                [
                    "method": op.method.jsonSafe,
                    "url": op.url.jsonSafe,
                    "length": op.length.jsonSafe,
                    "offset": op.offset.jsonSafe
                ] as [String: Any]
            }
        }

        return result
    }
}
