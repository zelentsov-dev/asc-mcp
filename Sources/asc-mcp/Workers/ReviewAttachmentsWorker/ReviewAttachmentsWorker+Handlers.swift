import Foundation
import MCP

// MARK: - Tool Handlers
extension ReviewAttachmentsWorker {

    /// Uploads a review attachment (full cycle: reserve → upload → commit)
    /// - Returns: JSON with final attachment info
    func uploadAttachment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let reviewDetailId = arguments["review_detail_id"]?.stringValue,
              let filePath = arguments["file_path"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: review_detail_id, file_path")],
                isError: true
            )
        }

        do {
            // Step 1: Get file info
            let fileSize = try await uploadService.fileSize(at: filePath)
            let fileName = await uploadService.fileName(at: filePath)

            // Step 2: Reserve — POST to create attachment reservation
            let createRequest = CreateReviewAttachmentRequest(
                data: CreateReviewAttachmentRequest.CreateData(
                    attributes: CreateReviewAttachmentRequest.Attributes(
                        fileSize: fileSize,
                        fileName: fileName
                    ),
                    relationships: CreateReviewAttachmentRequest.Relationships(
                        appStoreReviewDetail: CreateReviewAttachmentRequest.ReviewDetailRelationship(
                            data: ASCResourceIdentifier(type: "appStoreReviewDetails", id: reviewDetailId)
                        )
                    )
                )
            )

            let encoder = JSONEncoder()
            let bodyData = try encoder.encode(createRequest)
            let reserveData = try await httpClient.post("/v1/appStoreReviewAttachments", body: bodyData)
            let reserveResponse = try JSONDecoder().decode(ASCReviewAttachmentResponse.self, from: reserveData)

            let attachmentId = reserveResponse.data.id
            guard let uploadOperations = reserveResponse.data.attributes?.uploadOperations, !uploadOperations.isEmpty else {
                return CallTool.Result(
                    content: [.text("Error: No upload operations returned from reservation")],
                    isError: true
                )
            }

            // Step 3: Upload file chunks
            let md5 = try await uploadService.uploadFile(filePath: filePath, uploadOperations: uploadOperations)

            // Step 4: Commit — PATCH to finalize upload
            let commitRequest = CommitReviewAttachmentRequest(
                data: CommitReviewAttachmentRequest.CommitData(
                    id: attachmentId,
                    attributes: CommitReviewAttachmentRequest.Attributes(
                        sourceFileChecksum: md5,
                        uploaded: true
                    )
                )
            )

            let commitBody = try encoder.encode(commitRequest)
            let commitData = try await httpClient.patch("/v1/appStoreReviewAttachments/\(attachmentId)", body: commitBody)
            let commitResponse = try JSONDecoder().decode(ASCReviewAttachmentResponse.self, from: commitData)

            let result = [
                "success": true,
                "attachment": formatAttachment(commitResponse.data)
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to upload review attachment: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a specific review attachment
    /// - Returns: JSON with attachment details
    func getAttachment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let attachmentId = arguments["attachment_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'attachment_id' is missing")],
                isError: true
            )
        }

        do {
            let data = try await httpClient.get("/v1/appStoreReviewAttachments/\(attachmentId)")
            let response = try JSONDecoder().decode(ASCReviewAttachmentResponse.self, from: data)

            let result = [
                "success": true,
                "attachment": formatAttachment(response.data)
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get review attachment: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a review attachment
    /// - Returns: JSON confirmation
    func deleteAttachment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let attachmentId = arguments["attachment_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'attachment_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appStoreReviewAttachments/\(attachmentId)")

            let result = [
                "success": true,
                "message": "Review attachment '\(attachmentId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete review attachment: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists review attachments for a review detail
    /// - Returns: JSON array of attachments
    func listAttachments(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let reviewDetailId = arguments["review_detail_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'review_detail_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCReviewAttachmentsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCReviewAttachmentsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/appStoreReviewDetails/\(reviewDetailId)/appStoreReviewAttachments",
                    parameters: queryParams,
                    as: ASCReviewAttachmentsResponse.self
                )
            }

            let attachments = response.data.map { formatAttachment($0) }

            var result: [String: Any] = [
                "success": true,
                "attachments": attachments,
                "count": attachments.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list review attachments: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatAttachment(_ attachment: ASCReviewAttachment) -> [String: Any] {
        var result: [String: Any] = [
            "id": attachment.id,
            "type": attachment.type,
            "fileName": attachment.attributes?.fileName.jsonSafe,
            "fileSize": attachment.attributes?.fileSize.jsonSafe,
            "sourceFileChecksum": attachment.attributes?.sourceFileChecksum.jsonSafe
        ]

        if let deliveryState = attachment.attributes?.assetDeliveryState {
            result["assetDeliveryState"] = [
                "state": deliveryState.state.jsonSafe,
                "errors": deliveryState.errors?.map { ["code": $0.code.jsonSafe, "description": $0.description.jsonSafe] } ?? []
            ]
        }

        return result
    }
}
