import Foundation
import MCP

// MARK: - Tool Handlers
extension ReviewAttachmentsWorker {

    /// Uploads a review attachment and confirms Apple's terminal delivery state
    /// - Returns: JSON with final attachment info
    func uploadAttachment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let reviewDetailId = arguments["review_detail_id"]?.stringValue,
              let filePath = arguments["file_path"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: review_detail_id, file_path")],
                isError: true
            )
        }

        let fileSize: Int
        let fileName: String
        do {
            fileSize = try await uploadService.fileSize(at: filePath)
            fileName = await uploadService.fileName(at: filePath)
        } catch {
            return MCPResult.error("Failed to read review attachment: \(error.localizedDescription)")
        }

        let reserveResponse: ASCReviewAttachmentResponse
        do {
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
            reserveResponse = try JSONDecoder().decode(ASCReviewAttachmentResponse.self, from: reserveData)
        } catch {
            return MCPResult.error("Failed to reserve review attachment: \(error.localizedDescription)")
        }

        let attachmentId = reserveResponse.data.id
        guard let uploadOperations = reserveResponse.data.attributes?.uploadOperations, !uploadOperations.isEmpty else {
            let cleanup = await rollbackReservation(attachmentId)
            return preCommitFailureResult(
                "Apple returned no upload operations for the review attachment reservation.",
                attachment: reserveResponse.data,
                cleanup: cleanup
            )
        }

        let md5: String
        do {
            md5 = try await uploadService.uploadFile(filePath: filePath, uploadOperations: uploadOperations)
        } catch {
            let cleanup = await rollbackReservation(attachmentId)
            return preCommitFailureResult(
                "Failed to transfer review attachment bytes: \(error.localizedDescription)",
                attachment: reserveResponse.data,
                cleanup: cleanup
            )
        }

        let commitBody: Data
        do {
            let commitRequest = CommitReviewAttachmentRequest(
                data: CommitReviewAttachmentRequest.CommitData(
                    id: attachmentId,
                    attributes: CommitReviewAttachmentRequest.Attributes(
                        sourceFileChecksum: md5,
                        uploaded: true
                    )
                )
            )

            commitBody = try JSONEncoder().encode(commitRequest)
        } catch {
            return retainedFailureResult(
                "Failed to prepare the review attachment commit: \(error.localizedDescription)",
                attachment: reserveResponse.data
            )
        }

        if Task.isCancelled {
            return retainedFailureResult(
                "Review attachment commit was not attempted because the operation was cancelled.",
                attachment: reserveResponse.data
            )
        }

        let commitData: Data
        do {
            commitData = try await httpClient.patch(
                "/v1/appStoreReviewAttachments/\(attachmentId)",
                body: commitBody
            )
        } catch {
            return await reconcileAfterCommit(
                attachmentId: attachmentId,
                lastKnownAttachment: reserveResponse.data,
                context: "The commit request did not return a confirmed response: \(error.localizedDescription)"
            )
        }

        let commitResponse: ASCReviewAttachmentResponse
        do {
            commitResponse = try JSONDecoder().decode(ASCReviewAttachmentResponse.self, from: commitData)
        } catch {
            return await reconcileAfterCommit(
                attachmentId: attachmentId,
                lastKnownAttachment: reserveResponse.data,
                context: "Apple returned an unreadable commit response: \(error.localizedDescription)"
            )
        }

        guard commitResponse.data.id == attachmentId,
              commitResponse.data.type == "appStoreReviewAttachments" else {
            return await reconcileAfterCommit(
                attachmentId: attachmentId,
                lastKnownAttachment: reserveResponse.data,
                context: "Apple returned a commit response for an unexpected attachment resource."
            )
        }

        return await resolveCommittedAttachment(commitResponse.data)
    }

    /// Gets details of a specific review attachment
    /// - Returns: JSON with attachment details
    func getAttachment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let attachmentId = arguments["attachment_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'attachment_id' is missing")],
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get review attachment: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'attachment_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appStoreReviewAttachments/\(attachmentId)")

            let result = [
                "success": true,
                "message": "Review attachment '\(attachmentId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to delete review attachment: \(error.localizedDescription)")],
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
                content: [MCPContent.text("Error: Required parameter 'review_detail_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCReviewAttachmentsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = await httpClient.parsePaginationUrl(nextUrl) {
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

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list review attachments: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatAttachment(_ attachment: ASCReviewAttachment) -> [String: Any] {
        var result: [String: Any] = [
            "id": attachment.id,
            "type": attachment.type,
            "fileName": (attachment.attributes?.fileName).jsonSafe,
            "fileSize": (attachment.attributes?.fileSize).jsonSafe,
            "sourceFileChecksum": (attachment.attributes?.sourceFileChecksum).jsonSafe
        ]

        if let deliveryState = attachment.attributes?.assetDeliveryState {
            result["assetDeliveryState"] = [
                "state": deliveryState.state.jsonSafe,
                "errors": formatDeliveryMessages(deliveryState.errors),
                "warnings": formatDeliveryMessages(deliveryState.warnings)
            ]
        }

        return result
    }

    private func resolveCommittedAttachment(_ attachment: ASCReviewAttachment) async -> CallTool.Result {
        switch attachment.attributes?.assetDeliveryState?.state {
        case "COMPLETE":
            return MCPResult.jsonObject([
                "success": true,
                "attachment": formatAttachment(attachment)
            ])
        case "FAILED":
            return retainedFailureResult(
                "Apple reported FAILED while processing the review attachment.",
                attachment: attachment
            )
        default:
            return await pollAttachmentDelivery(
                attachmentId: attachment.id,
                lastKnownAttachment: attachment,
                context: nil
            )
        }
    }

    private func reconcileAfterCommit(
        attachmentId: String,
        lastKnownAttachment: ASCReviewAttachment,
        context: String
    ) async -> CallTool.Result {
        if Task.isCancelled {
            return deliveryPendingResult(context, attachment: lastKnownAttachment)
        }

        return await pollAttachmentDelivery(
            attachmentId: attachmentId,
            lastKnownAttachment: lastKnownAttachment,
            context: context
        )
    }

    private func pollAttachmentDelivery(
        attachmentId: String,
        lastKnownAttachment: ASCReviewAttachment,
        context: String?
    ) async -> CallTool.Result {
        var latest = lastKnownAttachment

        for attempt in 0..<deliveryPollAttempts {
            if Task.isCancelled {
                return deliveryPendingResult(
                    context ?? "Review attachment delivery polling was cancelled.",
                    attachment: latest
                )
            }

            do {
                let data = try await httpClient.get("/v1/appStoreReviewAttachments/\(attachmentId)")
                let response = try JSONDecoder().decode(ASCReviewAttachmentResponse.self, from: data)
                guard response.data.id == attachmentId,
                      response.data.type == "appStoreReviewAttachments" else {
                    throw ASCError.parsing("Unexpected review attachment resource in reconciliation response")
                }
                latest = response.data
            } catch {
                let message = context.map { "\($0) Reconciliation also failed: \(error.localizedDescription)" }
                    ?? "The review attachment delivery state could not be confirmed: \(error.localizedDescription)"
                return deliveryPendingResult(message, attachment: latest)
            }

            switch latest.attributes?.assetDeliveryState?.state {
            case "COMPLETE":
                return MCPResult.jsonObject([
                    "success": true,
                    "attachment": formatAttachment(latest)
                ])
            case "FAILED":
                return retainedFailureResult(
                    "Apple reported FAILED while processing the review attachment.",
                    attachment: latest
                )
            default:
                break
            }

            if attempt + 1 < deliveryPollAttempts {
                if Task.isCancelled {
                    return deliveryPendingResult(
                        context ?? "Review attachment delivery polling was cancelled.",
                        attachment: latest
                    )
                }
                do {
                    try await Task.sleep(nanoseconds: deliveryPollIntervalNanoseconds)
                } catch {
                    return deliveryPendingResult(
                        context ?? "Review attachment delivery polling was cancelled.",
                        attachment: latest
                    )
                }
            }
        }

        let state = latest.attributes?.assetDeliveryState?.state ?? "unknown"
        let message = context.map { "\($0) Apple currently reports delivery state '\(state)'." }
            ?? "The review attachment was committed, but Apple still reports delivery state '\(state)'."
        return deliveryPendingResult(message, attachment: latest)
    }

    private func rollbackReservation(_ attachmentId: String) async -> ReviewAttachmentCleanupOutcome {
        do {
            _ = try await httpClient.delete("/v1/appStoreReviewAttachments/\(attachmentId)")
            return .deleted
        } catch let error as ASCError where error.httpStatusCode == 404 {
            return .alreadyAbsent
        } catch {
            return .failed(Redactor.redact(error.localizedDescription))
        }
    }

    private func preCommitFailureResult(
        _ message: String,
        attachment: ASCReviewAttachment,
        cleanup: ReviewAttachmentCleanupOutcome
    ) -> CallTool.Result {
        let safeMessage = Redactor.redact(message)
        let cleanupValue = cleanup.structuredValue(attachmentId: attachment.id)
        let manualGuidance = cleanup.reservationDeleted
            ? ""
            : " Use review_attachments_delete with attachment_id '\(attachment.id)' to retry cleanup."
        return MCPResult.jsonObject(
            [
                "success": false,
                "error": safeMessage,
                "attachmentId": attachment.id,
                "attachment": formatAttachment(attachment),
                "cleanup": cleanupValue,
                "reservationDeleted": cleanup.reservationDeleted
            ],
            text: "Error: \(safeMessage) Cleanup status: \(cleanup.status).\(manualGuidance)",
            isError: true
        )
    }

    private func retainedFailureResult(
        _ message: String,
        attachment: ASCReviewAttachment
    ) -> CallTool.Result {
        let safeMessage = Redactor.redact(message)
        return MCPResult.jsonObject(
            [
                "success": false,
                "error": safeMessage,
                "attachmentId": attachment.id,
                "attachment": formatAttachment(attachment),
                "deliveryPending": false,
                "cleanup": retainedCleanupGuidance(attachmentId: attachment.id),
                "reservationDeleted": false
            ],
            text: "Error: \(safeMessage) The attachment was retained. Inspect it with review_attachments_get and delete it explicitly with review_attachments_delete if appropriate.",
            isError: true
        )
    }

    private func deliveryPendingResult(
        _ message: String,
        attachment: ASCReviewAttachment
    ) -> CallTool.Result {
        let safeMessage = Redactor.redact(message)
        return MCPResult.jsonObject(
            [
                "success": false,
                "error": safeMessage,
                "attachmentId": attachment.id,
                "attachment": formatAttachment(attachment),
                "deliveryPending": true,
                "cleanup": retainedCleanupGuidance(attachmentId: attachment.id),
                "reservationDeleted": false
            ],
            text: "Error: \(safeMessage) The attachment was retained. Check it with review_attachments_get before using review_attachments_delete.",
            isError: true
        )
    }

    private func retainedCleanupGuidance(attachmentId: String) -> [String: Any] {
        [
            "status": "not_attempted",
            "attachmentId": attachmentId,
            "reason": "Automatic deletion was not attempted; inspect the attachment state before deleting it.",
            "tool": "review_attachments_delete",
            "arguments": ["attachment_id": attachmentId]
        ]
    }

    private func formatDeliveryMessages(_ messages: [ASCAssetDeliveryError]?) -> [[String: Any]] {
        messages?.map {
            [
                "code": $0.code.jsonSafe,
                "description": $0.description.jsonSafe
            ]
        } ?? []
    }
}

private enum ReviewAttachmentCleanupOutcome: Sendable {
    case deleted
    case alreadyAbsent
    case failed(String)

    var status: String {
        switch self {
        case .deleted:
            return "deleted"
        case .alreadyAbsent:
            return "already_absent"
        case .failed:
            return "failed"
        }
    }

    var reservationDeleted: Bool {
        switch self {
        case .deleted, .alreadyAbsent:
            return true
        case .failed:
            return false
        }
    }

    func structuredValue(attachmentId: String) -> [String: Any] {
        var value: [String: Any] = [
            "status": status,
            "attachmentId": attachmentId
        ]
        if case .failed(let reason) = self {
            value["reason"] = reason
            value["tool"] = "review_attachments_delete"
            value["arguments"] = ["attachment_id": attachmentId]
        }
        return value
    }
}

private extension ASCError {
    var httpStatusCode: Int? {
        switch self {
        case .api(_, let statusCode), .apiResponse(_, let statusCode):
            return statusCode
        default:
            return nil
        }
    }
}
