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

    /// Uploads a screenshot (full cycle: reserve, upload file, commit)
    /// - Returns: JSON with final screenshot info
    func uploadScreenshot(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let setId = arguments["set_id"]?.stringValue,
              let filePath = arguments["file_path"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: set_id, file_path")],
                isError: true
            )
        }

        do {
            // Step 1: Get file info
            let fileSize = try await uploadService.fileSize(at: filePath)
            let fileName = await uploadService.fileName(at: filePath)

            // Step 2: Reserve — POST to create screenshot reservation
            let createRequest = CreateScreenshotRequest(
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

            let encoder = JSONEncoder()
            let bodyData = try encoder.encode(createRequest)
            let reserveData = try await httpClient.post("/v1/appScreenshots", body: bodyData)
            let reserveResponse = try JSONDecoder().decode(ASCScreenshotResponse.self, from: reserveData)

            let screenshotId = reserveResponse.data.id
            guard let uploadOperations = reserveResponse.data.attributes?.uploadOperations, !uploadOperations.isEmpty else {
                return CallTool.Result(
                    content: [.text("Error: No upload operations returned from reservation")],
                    isError: true
                )
            }

            // Step 3: Upload file chunks
            let md5 = try await uploadService.uploadFile(filePath: filePath, uploadOperations: uploadOperations)

            // Step 4: Commit — PATCH to finalize upload
            let commitRequest = CommitScreenshotRequest(
                data: CommitScreenshotRequest.CommitData(
                    id: screenshotId,
                    attributes: CommitScreenshotRequest.Attributes(
                        sourceFileChecksum: md5,
                        uploaded: true
                    )
                )
            )

            let commitBody = try encoder.encode(commitRequest)
            let commitData = try await httpClient.patch("/v1/appScreenshots/\(screenshotId)", body: commitBody)
            let commitResponse = try JSONDecoder().decode(ASCScreenshotResponse.self, from: commitData)

            let result = [
                "success": true,
                "screenshot": formatScreenshot(commitResponse.data)
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to upload screenshot: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a specific screenshot
    /// - Returns: JSON with screenshot details
    func getScreenshot(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let screenshotId = arguments["screenshot_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'screenshot_id' is missing")],
                isError: true
            )
        }

        do {
            let data = try await httpClient.get("/v1/appScreenshots/\(screenshotId)")
            let response = try JSONDecoder().decode(ASCScreenshotResponse.self, from: data)

            let result = [
                "success": true,
                "screenshot": formatScreenshot(response.data)
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get screenshot: \(error.localizedDescription)")],
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

    /// Uploads an app preview (full cycle: reserve, upload file, commit)
    /// - Returns: JSON with final preview info
    func uploadPreview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let setId = arguments["set_id"]?.stringValue,
              let filePath = arguments["file_path"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: set_id, file_path")],
                isError: true
            )
        }

        let mimeType = arguments["mime_type"]?.stringValue ?? "video/mp4"

        do {
            // Step 1: Get file info
            let fileSize = try await uploadService.fileSize(at: filePath)
            let fileName = await uploadService.fileName(at: filePath)

            // Step 2: Reserve — POST to create preview reservation
            let createRequest = CreatePreviewRequest(
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

            let encoder = JSONEncoder()
            let bodyData = try encoder.encode(createRequest)
            let reserveData = try await httpClient.post("/v1/appPreviews", body: bodyData)
            let reserveResponse = try JSONDecoder().decode(ASCPreviewResponse.self, from: reserveData)

            let previewId = reserveResponse.data.id
            guard let uploadOperations = reserveResponse.data.attributes?.uploadOperations, !uploadOperations.isEmpty else {
                return CallTool.Result(
                    content: [.text("Error: No upload operations returned from reservation")],
                    isError: true
                )
            }

            // Step 3: Upload file chunks
            let md5 = try await uploadService.uploadFile(filePath: filePath, uploadOperations: uploadOperations)

            // Step 4: Commit — PATCH to finalize upload
            let commitRequest = CommitPreviewRequest(
                data: CommitPreviewRequest.CommitData(
                    id: previewId,
                    attributes: CommitPreviewRequest.Attributes(
                        sourceFileChecksum: md5,
                        uploaded: true
                    )
                )
            )

            let commitBody = try encoder.encode(commitRequest)
            let commitData = try await httpClient.patch("/v1/appPreviews/\(previewId)", body: commitBody)
            let commitResponse = try JSONDecoder().decode(ASCPreviewResponse.self, from: commitData)

            let result = [
                "success": true,
                "preview": formatPreview(commitResponse.data)
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to upload preview: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a specific app preview
    /// - Returns: JSON with preview details
    func getPreview(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let previewId = arguments["preview_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'preview_id' is missing")],
                isError: true
            )
        }

        do {
            let data = try await httpClient.get("/v1/appPreviews/\(previewId)")
            let response = try JSONDecoder().decode(ASCPreviewResponse.self, from: data)

            let result = [
                "success": true,
                "preview": formatPreview(response.data)
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get preview: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'set_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPreviewsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCPreviewsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/appPreviewSets/\(setId)/appPreviews",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list previews: \(error.localizedDescription)")],
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
