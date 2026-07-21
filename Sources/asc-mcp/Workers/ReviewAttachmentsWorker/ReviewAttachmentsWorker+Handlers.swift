import Foundation
import MCP
import os

private let reviewAttachmentReadFields = "fileSize,fileName,sourceFileChecksum,assetDeliveryState,appStoreReviewDetail"
private let reviewAttachmentResourceType = "appStoreReviewAttachments"
private let reviewDetailResourceType = "appStoreReviewDetails"

// MARK: - Tool Handlers
extension ReviewAttachmentsWorker {

    /// Uploads a review attachment and reconciles Apple's asynchronous delivery state
    /// - Returns: JSON with terminal or accepted processing-pending attachment info
    func uploadAttachment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters 'review_detail_id' and 'file_path' are missing")
        }

        let reviewDetailID: String
        let filePath: String
        do {
            reviewDetailID = try reviewAttachmentIdentifier(
                "review_detail_id",
                from: arguments
            )
            filePath = try reviewAttachmentFilePath(arguments["file_path"])
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate review attachment upload")
        }

        let semanticValidation = ReviewAttachmentSemanticValidationState()
        let rawOutcome: UploadTransactionOutcome<ASCReviewAttachment> = await UploadTransactionRecovery.perform(
            filePath: filePath,
            resourceName: "review attachment",
            expectedType: reviewAttachmentResourceType,
            reservationEndpoint: "/v1/appStoreReviewAttachments",
            httpClient: httpClient,
            uploadService: uploadService,
            validateReservedResource: { attachment, snapshot in
                guard attachment.attributes?.fileName == snapshot.fileName,
                      attachment.attributes?.fileSize == snapshot.fileSize else {
                    throw ReviewAttachmentInputError(
                        "reservation fileName and fileSize must exactly match the immutable upload snapshot"
                    )
                }
                guard attachment.attributes?.assetDeliveryState?.state == "AWAITING_UPLOAD" else {
                    throw ReviewAttachmentInputError(
                        "reservation delivery state must be exactly AWAITING_UPLOAD before transfer"
                    )
                }
            },
            deliveryPollAttempts: deliveryPollAttempts,
            deliveryPollIntervalNanoseconds: deliveryPollIntervalNanoseconds,
            makeReservationBody: { fileSize, fileName in
                try JSONEncoder().encode(
                    CreateReviewAttachmentRequest(
                        data: CreateReviewAttachmentRequest.CreateData(
                            attributes: CreateReviewAttachmentRequest.Attributes(
                                fileSize: fileSize,
                                fileName: fileName
                            ),
                            relationships: CreateReviewAttachmentRequest.Relationships(
                                appStoreReviewDetail: CreateReviewAttachmentRequest.ReviewDetailRelationship(
                                    data: ASCResourceIdentifier(
                                        type: reviewDetailResourceType,
                                        id: reviewDetailID
                                    )
                                )
                            )
                        )
                    )
                )
            },
            decodeResource: { data in
                let response = try JSONDecoder().decode(
                    ASCReviewAttachmentResponse.self,
                    from: data
                )
                do {
                    try validateReviewAttachmentResponse(
                        response,
                        expectedID: semanticValidation.expectedResourceID(),
                        expectedReviewDetailID: reviewDetailID,
                        requireReviewDetailLineage: false,
                        requiredQuery: [:],
                        httpClient: httpClient,
                        context: "review attachment upload response"
                    )
                    semanticValidation.establishResourceID(response.data.id)
                    return response.data
                } catch {
                    semanticValidation.record(error)
                    throw error
                }
            },
            makeCommitBody: { attachmentID, checksum in
                try JSONEncoder().encode(
                    CommitReviewAttachmentRequest(
                        data: CommitReviewAttachmentRequest.CommitData(
                            id: attachmentID,
                            attributes: CommitReviewAttachmentRequest.Attributes(
                                sourceFileChecksum: checksum,
                                uploaded: true
                            )
                        )
                    )
                )
            },
            resourceEndpoint: reviewAttachmentEndpoint
        )
        let outcome = semanticValidation.enforcing(rawOutcome)

        return reviewAttachmentUploadResult(
            outcome,
            reviewDetailID: reviewDetailID
        )
    }

    /// Gets details of a specific review attachment
    /// - Returns: JSON with attachment details
    func getAttachment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'attachment_id' is missing")
        }

        do {
            let attachmentID = try reviewAttachmentIdentifier("attachment_id", from: arguments)
            let query = [
                "fields[appStoreReviewAttachments]": reviewAttachmentReadFields,
                "fields[appStoreReviewDetails]": "appStoreVersion",
                "include": "appStoreReviewDetail"
            ]
            let response: ASCReviewAttachmentResponse = try await httpClient.get(
                reviewAttachmentEndpoint(attachmentID),
                parameters: query,
                as: ASCReviewAttachmentResponse.self
            )
            try validateReviewAttachmentResponse(
                response,
                expectedID: attachmentID,
                requireReviewDetailLineage: true,
                requiredQuery: query,
                httpClient: httpClient,
                context: "review attachment get response"
            )

            return MCPResult.jsonObject([
                "success": true,
                "attachment": formatAttachment(response.data)
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to get review attachment")
        }
    }

    /// Deletes a review attachment
    /// - Returns: JSON confirmation
    func deleteAttachment(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error(
                "Required parameters 'attachment_id' and 'confirm_attachment_id' are missing"
            )
        }

        let attachmentID: String
        do {
            attachmentID = try reviewAttachmentIdentifier("attachment_id", from: arguments)
            let confirmationID = try reviewAttachmentIdentifier(
                "confirm_attachment_id",
                from: arguments
            )
            guard confirmationID == attachmentID else {
                throw ReviewAttachmentInputError(
                    "confirm_attachment_id must exactly match attachment_id"
                )
            }
        } catch {
            return MCPResult.error(error, prefix: "Failed to validate review attachment deletion")
        }

        do {
            _ = try await httpClient.delete(reviewAttachmentEndpoint(attachmentID))
            return MCPResult.jsonObject([
                "success": true,
                "attachment_id": attachmentID,
                "message": "Review attachment '\(attachmentID)' deleted"
            ])
        } catch {
            let base = MCPResult.error(error, prefix: "Failed to delete review attachment")
            return reviewAttachmentResult(
                base,
                adding: [
                    "attachment_id": .string(attachmentID),
                    "retrySafe": .bool(false),
                    "inspection": .object([
                        "tool": .string("review_attachments_get"),
                        "arguments": .object([
                            "attachment_id": .string(attachmentID)
                        ]),
                        "instruction": .string(
                            "Inspect the exact attachment before another delete attempt."
                        )
                    ])
                ]
            )
        }
    }

    /// Lists review attachments for a review detail
    /// - Returns: JSON array of attachments
    func listAttachments(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'review_detail_id' is missing")
        }

        do {
            let reviewDetailID = try reviewAttachmentIdentifier(
                "review_detail_id",
                from: arguments
            )
            let effectiveLimit = try reviewAttachmentLimit(arguments["limit"])
            let query = [
                "fields[appStoreReviewAttachments]": reviewAttachmentReadFields,
                "fields[appStoreReviewDetails]": "appStoreVersion",
                "include": "appStoreReviewDetail",
                "limit": String(effectiveLimit)
            ]
            let path = "/v1/appStoreReviewDetails/\(try ASCPathSegment.encode(reviewDetailID, field: "review_detail_id"))/appStoreReviewAttachments"
            let response: ASCReviewAttachmentsResponse
            let requestedCursor: String?

            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                let requestedLink = try validateReviewAttachmentLink(
                    nextURL,
                    expectedPath: path,
                    requiredQuery: query,
                    allowedQuery: Set(query.keys).union(["cursor"]),
                    httpClient: httpClient,
                    context: "review attachment requested continuation"
                )
                guard let cursor = requestedLink["cursor"],
                      !cursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ReviewAttachmentInputError(
                        "review attachment requested continuation omitted a non-empty cursor"
                    )
                }
                requestedCursor = cursor
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope.strict(path: path, query: query),
                    as: ASCReviewAttachmentsResponse.self
                )
            } else {
                requestedCursor = nil
                response = try await httpClient.get(
                    path,
                    parameters: query,
                    as: ASCReviewAttachmentsResponse.self
                )
            }

            var seenIDs = Set<String>()
            for attachment in response.data {
                try validateReviewAttachmentResource(
                    attachment,
                    expectedReviewDetailID: reviewDetailID,
                    requireReviewDetailLineage: true,
                    context: "review attachment list response"
                )
                guard seenIDs.insert(attachment.id).inserted else {
                    throw ReviewAttachmentInputError(
                        "review attachment list response contains a duplicate resource ID"
                    )
                }
            }

            try validateReviewAttachmentPaging(
                response,
                expectedPath: path,
                requiredQuery: query,
                requestedCursor: requestedCursor,
                requestedLimit: effectiveLimit,
                httpClient: httpClient,
                context: "review attachment list response"
            )

            let attachments = response.data.map(formatAttachment)
            var result: [String: Any] = [
                "success": true,
                "attachments": attachments,
                "count": attachments.count
            ]
            if let next = response.links.next {
                result["next_url"] = next
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list review attachments")
        }
    }

    // MARK: - Formatting

    private func formatAttachment(_ attachment: ASCReviewAttachment) -> [String: Any] {
        var result: [String: Any] = [
            "id": attachment.id,
            "type": attachment.type,
            "fileName": (attachment.attributes?.fileName).jsonSafe,
            "fileSize": (attachment.attributes?.fileSize).jsonSafe,
            "sourceFileChecksum": (attachment.attributes?.sourceFileChecksum).jsonSafe,
            "appStoreReviewDetailId": (attachment.relationships?.appStoreReviewDetail?.data?.id).jsonSafe
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

    private func formatDeliveryMessages(_ messages: [ASCAssetDeliveryError]?) -> [[String: Any]] {
        messages?.map {
            [
                "code": $0.code.jsonSafe,
                "description": $0.description.jsonSafe
            ]
        } ?? []
    }

    private func reviewAttachmentUploadResult(
        _ outcome: UploadTransactionOutcome<ASCReviewAttachment>,
        reviewDetailID: String
    ) -> CallTool.Result {
        let result = UploadTransactionRecovery.result(
            for: outcome,
            descriptor: UploadRecoveryDescriptor(
                resourceName: "review attachment",
                successKey: "attachment",
                idArgument: "attachment_id",
                getTool: "review_attachments_get",
                getIDArgument: "attachment_id",
                deleteTool: "review_attachments_delete",
                deleteConfirmationArgument: "confirm_attachment_id",
                inspectionTool: "review_attachments_list",
                inspectionArguments: ["review_detail_id": reviewDetailID],
                inspectionPageLimit: 200,
                inspectionNextURLArgument: "next_url"
            ),
            format: formatAttachment
        )

        var additions: [String: Value] = [:]
        if case .object(let payload)? = result.structuredContent,
           case .string(let attachmentID)? = payload["attachment_id"] {
            additions["attachmentId"] = .string(attachmentID)
        }

        switch outcome {
        case .reservationUnresolved(_, let fingerprint),
             .reservationCommittedUnverified(_, _, let fingerprint):
            if let fingerprint {
                additions["reservationHints"] = .object([
                    "fileName": .string(fingerprint.fileName),
                    "fileSize": .int(fingerprint.fileSize),
                    "matchStrength": .string("non_unique"),
                    "checksumAvailableBeforeCommit": .bool(false)
                ])
            }
            additions["manualResolutionRequired"] = .bool(true)
            additions["manualResolution"] = reviewAttachmentManualReservationResolution(
                reviewDetailID: reviewDetailID
            )

        case .preCommitFailure(_, _, _, let checksumReceipt):
            if let checksumReceipt {
                additions["sourceFileChecksumReceipt"] = .string(checksumReceipt)
            }

        default:
            break
        }

        return additions.isEmpty
            ? result
            : reviewAttachmentResult(result, adding: additions)
    }
}

private func reviewAttachmentIdentifier(
    _ name: String,
    from arguments: [String: Value]
) throws -> String {
    guard let value = arguments[name]?.stringValue else {
        throw ReviewAttachmentInputError("\(name) must be a string")
    }
    let encoded = try ASCPathSegment.encode(value, field: name)
    guard encoded == value else {
        throw ReviewAttachmentInputError(
            "\(name) must be a canonical App Store Connect resource ID"
        )
    }
    return value
}

private func reviewAttachmentFilePath(_ value: Value?) throws -> String {
    guard let path = value?.stringValue else {
        throw ReviewAttachmentInputError("file_path must be a string")
    }
    guard (path as NSString).isAbsolutePath else {
        throw ReviewAttachmentInputError("file_path must be an absolute path")
    }
    return path
}

private func reviewAttachmentLimit(_ value: Value?) throws -> Int {
    guard let value else { return 25 }
    guard let limit = value.intValue, (1...200).contains(limit) else {
        throw ReviewAttachmentInputError("limit must be an integer between 1 and 200")
    }
    return limit
}

private func reviewAttachmentEndpoint(_ attachmentID: String) throws -> String {
    let encoded = try ASCPathSegment.encode(
        attachmentID,
        field: "review attachment response ID"
    )
    guard encoded == attachmentID else {
        throw ReviewAttachmentInputError(
            "review attachment response ID must be canonical"
        )
    }
    return "/v1/appStoreReviewAttachments/\(try ASCPathSegment.encode(attachmentID, field: "review attachment response ID"))"
}

private func validateReviewAttachmentResource(
    _ attachment: ASCReviewAttachment,
    expectedID: String? = nil,
    expectedReviewDetailID: String? = nil,
    requireReviewDetailLineage: Bool,
    context: String
) throws {
    try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
        type: attachment.type,
        id: attachment.id,
        expectedType: reviewAttachmentResourceType,
        expectedID: expectedID,
        context: context
    )

    guard let relationship = attachment.relationships?.appStoreReviewDetail else {
        if requireReviewDetailLineage {
            throw ReviewAttachmentInputError(
                "\(context) omitted appStoreReviewDetail lineage"
            )
        }
        return
    }
    guard let linkage = relationship.data else {
        throw ReviewAttachmentInputError(
            "\(context) returned appStoreReviewDetail without resource linkage"
        )
    }
    try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
        type: linkage.type,
        id: linkage.id,
        expectedType: reviewDetailResourceType,
        expectedID: expectedReviewDetailID,
        context: "\(context) appStoreReviewDetail lineage"
    )
}

private func validateReviewAttachmentResponse(
    _ response: ASCReviewAttachmentResponse,
    expectedID: String? = nil,
    expectedReviewDetailID: String? = nil,
    requireReviewDetailLineage: Bool,
    requiredQuery: [String: String],
    httpClient: HTTPClient,
    context: String
) throws {
    try validateReviewAttachmentResource(
        response.data,
        expectedID: expectedID,
        expectedReviewDetailID: expectedReviewDetailID,
        requireReviewDetailLineage: requireReviewDetailLineage,
        context: context
    )
    _ = try validateReviewAttachmentLink(
        response.links.`self`,
        expectedPath: reviewAttachmentEndpoint(response.data.id),
        requiredQuery: requiredQuery,
        allowedQuery: Set(requiredQuery.keys),
        httpClient: httpClient,
        context: "\(context) links.self"
    )
}

private func validateReviewAttachmentPaging(
    _ response: ASCReviewAttachmentsResponse,
    expectedPath: String,
    requiredQuery: [String: String],
    requestedCursor: String?,
    requestedLimit: Int,
    httpClient: HTTPClient,
    context: String
) throws {
    let allowedQuery = Set(requiredQuery.keys).union(["cursor"])
    let selfQuery = try validateReviewAttachmentLink(
        response.links.`self`,
        expectedPath: expectedPath,
        requiredQuery: requiredQuery,
        allowedQuery: allowedQuery,
        httpClient: httpClient,
        context: "\(context) links.self"
    )
    guard selfQuery["cursor"] == requestedCursor else {
        throw ReviewAttachmentInputError(
            "\(context) links.self does not identify the requested page cursor"
        )
    }

    let nextCursor: String?
    if let next = response.links.next {
        let nextQuery = try validateReviewAttachmentLink(
            next,
            expectedPath: expectedPath,
            requiredQuery: requiredQuery,
            allowedQuery: allowedQuery,
            httpClient: httpClient,
            context: "\(context) links.next"
        )
        guard let cursor = nextQuery["cursor"],
              !cursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              cursor != requestedCursor else {
            throw ReviewAttachmentInputError(
                "\(context) links.next must advance to a distinct non-empty cursor"
            )
        }
        nextCursor = cursor
    } else {
        nextCursor = nil
    }

    if let first = response.links.first {
        _ = try validateReviewAttachmentLink(
            first,
            expectedPath: expectedPath,
            requiredQuery: requiredQuery,
            allowedQuery: allowedQuery,
            httpClient: httpClient,
            context: "\(context) links.first"
        )
    }

    guard response.data.count <= requestedLimit else {
        throw ReviewAttachmentInputError(
            "\(context) contains more resources than the requested limit"
        )
    }
    guard let meta = response.meta else { return }
    guard let paging = meta.paging, let limit = paging.limit else {
        throw ReviewAttachmentInputError(
            "\(context) contains incomplete paging metadata"
        )
    }
    guard limit == requestedLimit, response.data.count <= limit else {
        throw ReviewAttachmentInputError(
            "\(context) paging limit does not match the requested collection scope"
        )
    }
    if let total = paging.total, total < response.data.count {
        throw ReviewAttachmentInputError(
            "\(context) contains an impossible paging total"
        )
    }
    if let metaCursor = paging.nextCursor {
        guard !metaCursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              metaCursor == nextCursor else {
            throw ReviewAttachmentInputError(
                "\(context) paging cursor does not match links.next"
            )
        }
    }
}

private func validateReviewAttachmentLink(
    _ value: String,
    expectedPath: String,
    requiredQuery: [String: String],
    allowedQuery: Set<String>,
    httpClient: HTTPClient,
    context: String
) throws -> [String: String] {
    do {
        return try httpClient.validatedScopedLink(
            value,
            scope: PaginationScope(
                path: expectedPath,
                requiredParameters: requiredQuery,
                allowedParameters: allowedQuery
            )
        ).parameters
    } catch {
        throw ReviewAttachmentInputError(
            "Apple returned an invalid or out-of-origin link in \(context): \(Redactor.redact(error.localizedDescription))"
        )
    }
}

private func reviewAttachmentManualReservationResolution(reviewDetailID: String) -> Value {
    .object([
        "reason": .string(
            "fileName and fileSize are non-unique hints, and sourceFileChecksum is unavailable on an uncommitted reservation"
        ),
        "inspect": .object([
            "tool": .string("review_attachments_list"),
            "arguments": .object([
                "review_detail_id": .string(reviewDetailID),
                "limit": .int(200)
            ]),
            "continue_with_next_url": .bool(true),
            "instruction": .string(
                "Inspect every page; the hints cannot prove which reservation belongs to this request."
            )
        ]),
        "verify": .object([
            "tool": .string("review_attachments_get"),
            "id_argument": .string("attachment_id"),
            "instruction": .string(
                "Verify each possible candidate by its exact attachment ID before any cleanup."
            )
        ]),
        "cleanup": .object([
            "tool": .string("review_attachments_delete"),
            "id_argument": .string("attachment_id"),
            "confirmation_argument": .string("confirm_attachment_id"),
            "instruction": .string(
                "Delete only an exact manually verified attachment ID and repeat that same ID as confirmation."
            )
        ]),
        "retry": .string(
            "Do not create another reservation until manual inspection has resolved whether Apple committed the original POST."
        )
    ])
}

private final class ReviewAttachmentSemanticValidationState: Sendable {
    private struct State: Sendable {
        var expectedResourceID: String? = nil
        var firstFailure: String? = nil
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

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

    func enforcing(
        _ outcome: UploadTransactionOutcome<ASCReviewAttachment>
    ) -> UploadTransactionOutcome<ASCReviewAttachment> {
        guard let failure = state.withLock({ $0.firstFailure }) else {
            return outcome
        }
        let message = "A confirmed review attachment response violated immutable identity, lineage, or document-link scope: \(failure) Later reconciliation cannot override that semantic conflict."
        switch outcome {
        case .success(let resource, _),
             .processingPending(_, let resource, _):
            return .commitUnresolved(message, resource)
        default:
            return outcome
        }
    }
}

private func reviewAttachmentResult(
    _ result: CallTool.Result,
    adding fields: [String: Value]
) -> CallTool.Result {
    guard case .object(var payload)? = result.structuredContent else {
        return result
    }
    for (key, value) in fields where payload[key] == nil {
        payload[key] = value
    }

    let firstText = result.content.compactMap { content -> String? in
        guard case .text(let text, _, _) = content else { return nil }
        return text
    }.first
    let humanText = firstText?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") == true
        ? nil
        : firstText
    return MCPResult.json(
        .object(payload),
        text: humanText,
        isError: result.isError == true,
        _meta: result._meta
    )
}

private struct ReviewAttachmentInputError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
