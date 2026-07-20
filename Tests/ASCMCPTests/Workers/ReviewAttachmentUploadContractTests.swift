import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Review Attachment Upload Contract Tests")
struct ReviewAttachmentUploadContractTests {
    @Test("complete commit response succeeds without polling")
    func completeCommitResponseSucceedsWithoutPolling() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentResponse(state: "AWAITING_UPLOAD", includeUploadOperation: true)),
            .init(statusCode: 200, body: reviewAttachmentResponse(state: "COMPLETE", includeMessages: true))
        ])
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])
        let worker = try await makeReviewAttachmentWorker(apiTransport: apiTransport, uploadTransport: uploadTransport)

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH"])
        #expect(requests.map { $0.url?.path } == [
            "/v1/appStoreReviewAttachments",
            "/v1/appStoreReviewAttachments/attachment-1"
        ])

        let reserveBody = try reviewAttachmentJSONBody(requests[0])
        let reserveData = try reviewAttachmentDictionary(reserveBody["data"])
        let reserveAttributes = try reviewAttachmentDictionary(reserveData["attributes"])
        let relationships = try reviewAttachmentDictionary(reserveData["relationships"])
        let reviewDetail = try reviewAttachmentDictionary(relationships["appStoreReviewDetail"])
        let linkage = try reviewAttachmentDictionary(reviewDetail["data"])
        #expect(reserveData["type"] as? String == "appStoreReviewAttachments")
        #expect(reserveAttributes["fileName"] as? String == fileURL.lastPathComponent)
        #expect(reserveAttributes["fileSize"] as? Int == 5)
        #expect(linkage["type"] as? String == "appStoreReviewDetails")
        #expect(linkage["id"] as? String == "review-detail-1")

        let commitBody = try reviewAttachmentJSONBody(requests[1])
        let commitData = try reviewAttachmentDictionary(commitBody["data"])
        let commitAttributes = try reviewAttachmentDictionary(commitData["attributes"])
        #expect(commitData["id"] as? String == "attachment-1")
        #expect(commitAttributes["sourceFileChecksum"] as? String == "5d41402abc4b2a76b9719d911017c592")
        #expect(commitAttributes["uploaded"] as? Bool == true)

        let uploadRequest = try #require(await uploadTransport.recordedRequests().first)
        #expect(uploadRequest.httpMethod == "PUT")
        #expect(uploadRequest.httpBody == Data("hello".utf8))
        #expect(uploadRequest.value(forHTTPHeaderField: "Authorization") == nil)

        let payload = try reviewAttachmentObject(result.structuredContent)
        #expect(payload["success"] == .bool(true))
        let attachment = try reviewAttachmentValueObject(payload["attachment"])
        let deliveryState = try reviewAttachmentValueObject(attachment["assetDeliveryState"])
        let warnings = try reviewAttachmentArray(deliveryState["warnings"])
        #expect(deliveryState["state"] == .string("COMPLETE"))
        #expect(warnings.count == 1)
    }

    @Test("failed commit response is retained without polling or deletion")
    func failedCommitResponseIsRetained() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentResponse(state: "AWAITING_UPLOAD", includeUploadOperation: true)),
            .init(statusCode: 200, body: reviewAttachmentResponse(state: "FAILED", includeMessages: true))
        ])
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])
        let worker = try await makeReviewAttachmentWorker(apiTransport: apiTransport, uploadTransport: uploadTransport)

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError == true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH"])
        try assertRetained(result, state: "FAILED", pending: false)
    }

    @Test("nonterminal commit response polls to complete")
    func nonterminalCommitPollsToComplete() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentResponse(state: "AWAITING_UPLOAD", includeUploadOperation: true)),
            .init(statusCode: 200, body: reviewAttachmentResponse(state: "UPLOAD_COMPLETE")),
            .init(statusCode: 200, body: reviewAttachmentResponse(state: "COMPLETE"))
        ])
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])
        let worker = try await makeReviewAttachmentWorker(apiTransport: apiTransport, uploadTransport: uploadTransport)

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH", "GET"])
        let pollQuery = reviewAttachmentUploadQuery(requests[2])
        #expect(pollQuery["fields[appStoreReviewAttachments]"] == "fileSize,fileName,sourceFileChecksum,assetDeliveryState,appStoreReviewDetail")
        #expect(pollQuery["include"] == nil)
    }

    @Test("ambiguous commit error reconciles without deletion")
    func ambiguousCommitErrorReconcilesWithoutDeletion() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = ReviewAttachmentScriptTransport(steps: [
            .response(statusCode: 201, body: reviewAttachmentResponse(state: "AWAITING_UPLOAD", includeUploadOperation: true)),
            .rawNetworkFailure,
            .response(statusCode: 200, body: reviewAttachmentResponse(state: "COMPLETE"))
        ])
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])
        let worker = try await makeReviewAttachmentWorker(apiTransport: apiTransport, uploadTransport: uploadTransport)

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH", "GET"])
        #expect(requests.contains { $0.httpMethod == "DELETE" } == false)
    }

    @Test("malformed successful commit response with pending GET is accepted")
    func malformedCommitResponseIsAcceptedPending() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentResponse(state: "AWAITING_UPLOAD", includeUploadOperation: true)),
            .init(statusCode: 200, body: "{"),
            .init(statusCode: 200, body: reviewAttachmentResponse(state: "UPLOAD_COMPLETE"))
        ])
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])
        let worker = try await makeReviewAttachmentWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport,
            pollAttempts: 1
        )

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH", "GET"])
        try assertProcessingPending(result, state: "UPLOAD_COMPLETE")
    }

    @Test("cancellation after commit response prevents polling")
    func cancellationPreventsPolling() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = CancellingPatchTransport()
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])
        let worker = try await makeReviewAttachmentWorker(apiTransport: apiTransport, uploadTransport: uploadTransport)

        let task = Task {
            try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))
        }
        let result = try await task.value

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH"])
        try assertProcessingPending(result, state: "UPLOAD_COMPLETE")
    }

    @Test("ambiguous commit with only a pending GET remains unresolved")
    func ambiguousCommitWithPendingGetRemainsError() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = ReviewAttachmentScriptTransport(steps: [
            .response(statusCode: 201, body: reviewAttachmentResponse(state: "AWAITING_UPLOAD", includeUploadOperation: true)),
            .rawNetworkFailure,
            .response(statusCode: 200, body: reviewAttachmentResponse(state: "UPLOAD_COMPLETE"))
        ])
        let worker = try await makeReviewAttachmentWorker(
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")]),
            pollAttempts: 1
        )

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH", "GET"])
        try assertRetained(result, state: "UPLOAD_COMPLETE", pending: true)
        let payload = try reviewAttachmentObject(result.structuredContent)
        #expect(payload["uploadCommitted"] == nil)
    }

    @Test("confirmed malformed commit with failed GET is accepted pending")
    func confirmedMalformedCommitWithFailedGetIsAcceptedPending() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = ReviewAttachmentScriptTransport(steps: [
            .response(statusCode: 201, body: reviewAttachmentResponse(state: "AWAITING_UPLOAD", includeUploadOperation: true)),
            .response(statusCode: 200, body: "{"),
            .failure("GET unavailable")
        ])
        let worker = try await makeReviewAttachmentWorker(
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        )

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError != true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH", "GET"])
        try assertProcessingPending(result, state: "AWAITING_UPLOAD")
    }

    @Test("wrong commit attachment reconciles the expected attachment once")
    func wrongCommitAttachmentReconcilesExpectedAttachment() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentResponse(state: "AWAITING_UPLOAD", includeUploadOperation: true)),
            .init(statusCode: 200, body: reviewAttachmentResponse(
                state: "COMPLETE",
                type: "appScreenshots"
            )),
            .init(statusCode: 200, body: reviewAttachmentResponse(state: "COMPLETE"))
        ])
        let worker = try await makeReviewAttachmentWorker(
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        )

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH", "GET"])
        #expect(requests.contains { $0.httpMethod == "DELETE" } == false)
        let payload = try reviewAttachmentObject(result.structuredContent)
        #expect(payload["success"] == .bool(true))
        #expect(payload["reconciledAfterCommit"] == .bool(true))
    }

    @Test("wrong reconciliation attachment is retained as an error")
    func wrongReconciliationAttachmentRemainsError() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentResponse(state: "AWAITING_UPLOAD", includeUploadOperation: true)),
            .init(statusCode: 200, body: reviewAttachmentResponse(
                state: "COMPLETE",
                type: "appScreenshots"
            )),
            .init(statusCode: 200, body: reviewAttachmentResponse(
                state: "COMPLETE",
                type: "appScreenshots"
            ))
        ])
        let worker = try await makeReviewAttachmentWorker(
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        )

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH", "GET"])
        let payload = try reviewAttachmentObject(result.structuredContent)
        #expect(payload["retrySafe"] == .bool(false))
        #expect(payload["reservationDeleted"] == .bool(false))
    }

    @Test("failed state from polling is retained without deletion")
    func failedPolledStateIsRetained() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentResponse(state: "AWAITING_UPLOAD", includeUploadOperation: true)),
            .init(statusCode: 200, body: reviewAttachmentResponse(state: "UPLOAD_COMPLETE")),
            .init(statusCode: 200, body: reviewAttachmentResponse(state: "FAILED", includeMessages: true))
        ])
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])
        let worker = try await makeReviewAttachmentWorker(apiTransport: apiTransport, uploadTransport: uploadTransport)

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError == true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH", "GET"])
        try assertRetained(result, state: "FAILED", pending: false)
    }

    @Test("ambiguous reservation response is not retry safe")
    func ambiguousReservationIsNotRetrySafe() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = ReviewAttachmentScriptTransport(steps: [
            .rawNetworkFailure
        ])
        let worker = try await makeReviewAttachmentWorker(
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST"])
        let payload = try reviewAttachmentObject(result.structuredContent)
        #expect(payload["reservationIdKnown"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
    }

    @Test("cancellation after reservation rolls back without attempting PATCH")
    func cancellationAfterReservationRollsBack() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = ReviewAttachmentScriptTransport(steps: [
            .cancelAndResponse(
                statusCode: 201,
                body: reviewAttachmentResponse(state: "AWAITING_UPLOAD", includeUploadOperation: true)
            ),
            .response(statusCode: 204, body: "")
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await makeReviewAttachmentWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let task = Task {
            try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))
        }
        let result = try await task.value

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "DELETE"])
        #expect(await uploadTransport.recordedRequests().isEmpty)
        try assertCleanup(result, status: "deleted", reservationDeleted: true)
        let payload = try reviewAttachmentObject(result.structuredContent)
        #expect(payload["retrySafe"] == .bool(true))
    }

    @Test("unexpected reservation type is retained without deletion")
    func wrongReservationTypeIsNotDeleted() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentResponse(
                state: "AWAITING_UPLOAD",
                type: "appScreenshots"
            ))
        ])
        let worker = try await makeReviewAttachmentWorker(
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST"])
        let payload = try reviewAttachmentObject(result.structuredContent)
        #expect(payload["reservationIdKnown"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
    }

    @Test("missing upload operations rolls back the reservation")
    func missingUploadOperationsRollsBackReservation() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentResponse(state: "AWAITING_UPLOAD")),
            .init(statusCode: 204, body: "")
        ])
        let worker = try await makeReviewAttachmentWorker(
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError == true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "DELETE"])
        try assertCleanup(result, status: "deleted", reservationDeleted: true)
    }

    @Test("cleanup 404 is reported as already absent")
    func cleanupNotFoundIsAlreadyAbsent() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentResponse(state: "AWAITING_UPLOAD")),
            .init(statusCode: 404, body: reviewAttachmentAPIError(status: 404, code: "NOT_FOUND"))
        ])
        let worker = try await makeReviewAttachmentWorker(
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError == true)
        try assertCleanup(result, status: "already_absent", reservationDeleted: true)
    }

    @Test("presigned transfer failure rolls back before commit")
    func transferFailureRollsBackBeforeCommit() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentResponse(state: "AWAITING_UPLOAD", includeUploadOperation: true)),
            .init(statusCode: 204, body: "")
        ])
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 500, body: "")
        ])
        let worker = try await makeReviewAttachmentWorker(apiTransport: apiTransport, uploadTransport: uploadTransport)

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError == true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "DELETE"])
        try assertCleanup(result, status: "deleted", reservationDeleted: true)
    }

    @Test("transfer errors never expose review attachment upload credentials")
    func transferErrorsDoNotExposeUploadCredentials() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentResponse(
                state: "AWAITING_UPLOAD",
                includeUploadOperation: true,
                includeSecretHeader: true
            )),
            .init(statusCode: 204, body: "")
        ])
        let worker = try await makeReviewAttachmentWorker(
            apiTransport: apiTransport,
            uploadTransport: LeakingReviewAttachmentUploadTransport()
        )

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError == true)
        let text = reviewAttachmentText(result)
        #expect(reviewAttachmentContains(result.structuredContent, substring: "upload.example.test") == false)
        #expect(reviewAttachmentContains(result.structuredContent, substring: "signed-secret") == false)
        #expect(reviewAttachmentContains(result.structuredContent, substring: "header-secret") == false)
        #expect(text.contains("upload.example.test") == false)
        #expect(text.contains("signed-secret") == false)
        #expect(text.contains("header-secret") == false)
    }

    @Test("rollback failure includes manual cleanup guidance")
    func rollbackFailureIncludesGuidance() async throws {
        let fileURL = try reviewAttachmentFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: reviewAttachmentResponse(state: "AWAITING_UPLOAD")),
            .init(statusCode: 500, body: reviewAttachmentAPIError(status: 500, code: "UNEXPECTED_ERROR"))
        ])
        let worker = try await makeReviewAttachmentWorker(
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        let result = try await worker.handleTool(reviewAttachmentUploadParameters(fileURL: fileURL))

        #expect(result.isError == true)
        try assertCleanup(result, status: "failed", reservationDeleted: false)
        let payload = try reviewAttachmentObject(result.structuredContent)
        let cleanup = try reviewAttachmentValueObject(payload["cleanup"])
        #expect(cleanup["tool"] == .string("review_attachments_delete"))
        guard case .string(let reason) = cleanup["reason"] else {
            Issue.record("Expected redacted cleanup failure reason")
            return
        }
        #expect(reason.isEmpty == false)
        let arguments = try reviewAttachmentValueObject(cleanup["arguments"])
        #expect(arguments["attachment_id"] == .string("attachment-1"))
    }
}

private func makeReviewAttachmentWorker(
    apiTransport: any HTTPTransport,
    uploadTransport: any HTTPTransport,
    pollAttempts: Int = 3
) async throws -> ReviewAttachmentsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: apiTransport,
        maxRetries: 3
    )
    return ReviewAttachmentsWorker(
        httpClient: client,
        uploadService: UploadService(transport: uploadTransport, batchSize: 1),
        deliveryPollAttempts: pollAttempts,
        deliveryPollIntervalNanoseconds: 0
    )
}

private func reviewAttachmentUploadParameters(fileURL: URL) -> CallTool.Parameters {
    CallTool.Parameters(
        name: "review_attachments_upload",
        arguments: [
            "review_detail_id": .string("review-detail-1"),
            "file_path": .string(fileURL.path)
        ]
    )
}

private func reviewAttachmentFile(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("asc-mcp-review-attachment-\(UUID().uuidString).png")
    try data.write(to: url)
    return url
}

private func reviewAttachmentResponse(
    state: String,
    type: String = "appStoreReviewAttachments",
    includeUploadOperation: Bool = false,
    includeSecretHeader: Bool = false,
    includeMessages: Bool = false
) -> String {
    let requestHeaders = includeSecretHeader
        ? #"[{"name":"X-Amz-Security-Token","value":"header-secret"}]"#
        : "[]"
    let uploadOperations = includeUploadOperation
        ? #", "uploadOperations":[{"method":"PUT","url":"https://upload.example.test/chunk?signed=signed-secret","length":5,"offset":0,"requestHeaders":\#(requestHeaders)}]"#
        : ""
    let messages = includeMessages
        ? #", "errors":[{"code":"ASSET_ERROR","description":"The asset failed validation."}], "warnings":[{"code":"ASSET_WARNING","description":"The image was recompressed."}]"#
        : ""
    return #"{"data":{"type":"\#(type)","id":"attachment-1","attributes":{"fileSize":5,"fileName":"attachment.png","sourceFileChecksum":"5d41402abc4b2a76b9719d911017c592","assetDeliveryState":{"state":"\#(state)"\#(messages)}\#(uploadOperations)}}}"#
}

private func reviewAttachmentAPIError(status: Int, code: String) -> String {
    #"{"errors":[{"status":"\#(status)","code":"\#(code)","title":"Request failed","detail":"Request failed"}]}"#
}

private func reviewAttachmentJSONBody(_ request: URLRequest) throws -> [String: Any] {
    guard let body = request.httpBody,
          let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        throw ReviewAttachmentUploadContractTestFailure.expectedDictionary
    }
    return object
}

private func reviewAttachmentDictionary(_ value: Any?) throws -> [String: Any] {
    guard let dictionary = value as? [String: Any] else {
        throw ReviewAttachmentUploadContractTestFailure.expectedDictionary
    }
    return dictionary
}

private func reviewAttachmentObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected structured object")
        throw ReviewAttachmentUploadContractTestFailure.expectedObject
    }
    return object
}

private func reviewAttachmentValueObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected nested structured object")
        throw ReviewAttachmentUploadContractTestFailure.expectedObject
    }
    return object
}

private func reviewAttachmentArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        Issue.record("Expected structured array")
        throw ReviewAttachmentUploadContractTestFailure.expectedArray
    }
    return array
}

private func reviewAttachmentContains(_ value: Value?, substring: String) -> Bool {
    guard let value else { return false }
    switch value {
    case .string(let string):
        return string.contains(substring)
    case .array(let values):
        return values.contains { reviewAttachmentContains($0, substring: substring) }
    case .object(let object):
        return object.contains { key, value in
            key.contains(substring) || reviewAttachmentContains(value, substring: substring)
        }
    default:
        return false
    }
}

private func reviewAttachmentText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content {
            return text
        }
        return nil
    }.joined(separator: "\n")
}

private func reviewAttachmentUploadQuery(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(
        url: request.url!,
        resolvingAgainstBaseURL: false
    )?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

private func assertRetained(_ result: CallTool.Result, state: String, pending: Bool) throws {
    let payload = try reviewAttachmentObject(result.structuredContent)
    #expect(payload["attachmentId"] == .string("attachment-1"))
    #expect(payload["reservationDeleted"] == .bool(false))
    #expect(payload["deliveryPending"] == .bool(pending))
    let cleanup = try reviewAttachmentValueObject(payload["cleanup"])
    #expect(cleanup["status"] == .string("not_attempted"))
    #expect(cleanup["tool"] == .string("review_attachments_delete"))
    #expect(cleanup["inspectTool"] == .string("review_attachments_get"))
    let arguments = try reviewAttachmentValueObject(cleanup["arguments"])
    #expect(arguments["attachment_id"] == .string("attachment-1"))
    let attachment = try reviewAttachmentValueObject(payload["attachment"])
    let deliveryState = try reviewAttachmentValueObject(attachment["assetDeliveryState"])
    #expect(deliveryState["state"] == .string(state))
    let inspectArguments = try reviewAttachmentValueObject(cleanup["inspectArguments"])
    #expect(inspectArguments["attachment_id"] == .string("attachment-1"))
}

private func assertProcessingPending(_ result: CallTool.Result, state: String) throws {
    let payload = try reviewAttachmentObject(result.structuredContent)
    #expect(payload["success"] == .bool(true))
    #expect(payload["uploadCommitted"] == .bool(true))
    #expect(payload["processingComplete"] == .bool(false))
    #expect(payload["deliveryPending"] == .bool(true))
    #expect(payload["retrySafe"] == .bool(false))
    #expect(payload["reservationDeleted"] == .bool(false))
    #expect(payload["attachmentId"] == .string("attachment-1"))
    let attachment = try reviewAttachmentValueObject(payload["attachment"])
    let deliveryState = try reviewAttachmentValueObject(attachment["assetDeliveryState"])
    #expect(deliveryState["state"] == .string(state))
    let cleanup = try reviewAttachmentValueObject(payload["cleanup"])
    #expect(cleanup["inspectTool"] == .string("review_attachments_get"))
    let inspectArguments = try reviewAttachmentValueObject(cleanup["inspectArguments"])
    #expect(inspectArguments["attachment_id"] == .string("attachment-1"))
}

private func assertCleanup(
    _ result: CallTool.Result,
    status: String,
    reservationDeleted: Bool
) throws {
    let payload = try reviewAttachmentObject(result.structuredContent)
    #expect(payload["reservationDeleted"] == .bool(reservationDeleted))
    let cleanup = try reviewAttachmentValueObject(payload["cleanup"])
    #expect(cleanup["status"] == .string(status))
}

private actor ReviewAttachmentScriptTransport: HTTPTransport {
    enum Step: Sendable {
        case response(statusCode: Int, body: String)
        case cancelAndResponse(statusCode: Int, body: String)
        case rawNetworkFailure
        case failure(String)
    }

    private var steps: [Step]
    private var requests: [URLRequest] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !steps.isEmpty else {
            throw ASCError.network("No scripted response queued")
        }

        switch steps.removeFirst() {
        case .response(let statusCode, let body):
            return (
                Data(body.utf8),
                reviewAttachmentHTTPResponse(request: request, statusCode: statusCode)
            )
        case .cancelAndResponse(let statusCode, let body):
            withUnsafeCurrentTask { $0?.cancel() }
            return (
                Data(body.utf8),
                reviewAttachmentHTTPResponse(request: request, statusCode: statusCode)
            )
        case .rawNetworkFailure:
            throw URLError(.networkConnectionLost)
        case .failure(let message):
            throw ASCError.network(message)
        }
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private actor CancellingPatchTransport: HTTPTransport {
    private var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        switch request.httpMethod {
        case "POST":
            return (
                Data(reviewAttachmentResponse(state: "AWAITING_UPLOAD", includeUploadOperation: true).utf8),
                reviewAttachmentHTTPResponse(request: request, statusCode: 201)
            )
        case "PATCH":
            withUnsafeCurrentTask { $0?.cancel() }
            return (
                Data(reviewAttachmentResponse(state: "UPLOAD_COMPLETE").utf8),
                reviewAttachmentHTTPResponse(request: request, statusCode: 200)
            )
        default:
            throw ASCError.network("Unexpected request after cancellation")
        }
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private actor LeakingReviewAttachmentUploadTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw ASCError.network("LeakingReviewAttachmentUploadTransport only supports file uploads")
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        let url = request.url?.absoluteString ?? "missing-url"
        let headers = request.allHTTPHeaderFields ?? [:]
        throw ASCError.network("Transfer failed for \(url) with headers \(headers)")
    }
}

private func reviewAttachmentHTTPResponse(request: URLRequest, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url ?? URL(string: "https://api.example.test")!,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: nil
    )!
}

private enum ReviewAttachmentUploadContractTestFailure: Error {
    case expectedArray
    case expectedDictionary
    case expectedObject
}
