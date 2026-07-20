import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Upload Transaction Recovery Contract Tests")
struct UploadTransactionRecoveryContractTests {
    @Test("ambiguous reservation inspection binds an immutable fingerprint across every page")
    func ambiguousReservationInspectionIncludesFingerprintAndPaginationGuidance() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let descriptor = UploadRecoveryDescriptor(
            resourceName: "probe",
            successKey: "resource",
            idArgument: "resource_id",
            getTool: "probe_get",
            getIDArgument: "resource_id",
            deleteTool: "probe_delete",
            inspectionTool: "probe_list",
            inspectionArguments: ["parent_id": "parent-1"],
            inspectionPageLimit: 200,
            inspectionNextURLArgument: "next_url",
            reservationFingerprintKey: "reservationFingerprint",
            inspectionCandidateFields: ["file_name", "file_size"]
        )

        let ambiguousOutcome = try await performProbeReservation(
            fileURL: fileURL,
            apiTransport: UploadRecoveryScriptTransport(steps: [.rawNetworkFailure])
        )
        guard case .reservationUnresolved(_, let ambiguousFingerprint) = ambiguousOutcome else {
            Issue.record("Expected an unresolved reservation outcome")
            return
        }
        #expect(ambiguousFingerprint?.fileName == fileURL.lastPathComponent)
        #expect(ambiguousFingerprint?.fileSize == 5)
        #expect(ambiguousFingerprint?.checksum == "5d41402abc4b2a76b9719d911017c592")

        let result = UploadTransactionRecovery.result(
            for: ambiguousOutcome,
            descriptor: descriptor,
            format: { ["id": $0.id, "type": $0.type] }
        )

        let payload = try uploadRecoveryObject(result.structuredContent)
        let fingerprint = try uploadRecoveryValueObject(payload["reservationFingerprint"])
        #expect(fingerprint["file_name"] == .string(fileURL.lastPathComponent))
        #expect(fingerprint["file_size"] == .int(5))
        #expect(fingerprint["checksum"] == .string("5d41402abc4b2a76b9719d911017c592"))
        let inspection = try uploadRecoveryValueObject(payload["inspection"])
        #expect(inspection["tool"] == .string("probe_list"))
        let arguments = try uploadRecoveryValueObject(inspection["arguments"])
        #expect(arguments["parent_id"] == .string("parent-1"))
        #expect(arguments["limit"] == .int(200))
        #expect(inspection["continue_with_next_url"] == .bool(true))
        #expect(inspection["next_url_argument"] == .string("next_url"))
        let candidateMatch = try uploadRecoveryValueObject(inspection["candidate_match"])
        #expect(candidateMatch["fingerprint_key"] == .string("reservationFingerprint"))
        #expect(candidateMatch["candidate_fields"] == .array([.string("file_name"), .string("file_size")]))
        #expect(candidateMatch["require_unique_match_before_retry"] == .bool(true))
        #expect(uploadRecoveryText(result).contains("require a unique candidate match"))

        let acceptedOutcome = try await performProbeReservation(
            fileURL: fileURL,
            apiTransport: TestHTTPTransport(responses: [.init(statusCode: 202, body: "")])
        )
        guard case .reservationCommittedUnverified(
            let statusCode,
            _,
            let acceptedFingerprint
        ) = acceptedOutcome else {
            Issue.record("Expected an accepted but unverified reservation outcome")
            return
        }
        #expect(statusCode == 202)
        #expect(acceptedFingerprint == ambiguousFingerprint)
        let acceptedResult = UploadTransactionRecovery.result(
            for: acceptedOutcome,
            descriptor: descriptor,
            format: { ["id": $0.id, "type": $0.type] }
        )
        let acceptedPayload = try uploadRecoveryObject(acceptedResult.structuredContent)
        #expect(acceptedPayload["reservationFingerprint"] == payload["reservationFingerprint"])
        let acceptedInspection = try uploadRecoveryValueObject(acceptedPayload["inspection"])
        #expect(acceptedInspection["candidate_match"] == inspection["candidate_match"])
        #expect(uploadRecoveryText(acceptedResult).contains("require a unique candidate match"))

        let legacyResult = UploadTransactionRecovery.result(
            for: ambiguousOutcome,
            descriptor: UploadRecoveryDescriptor(
                resourceName: "probe",
                successKey: "resource",
                idArgument: "resource_id",
                getTool: "probe_get",
                getIDArgument: "resource_id",
                deleteTool: "probe_delete",
                inspectionTool: "probe_list",
                inspectionArguments: ["parent_id": "parent-1"]
            ),
            format: { ["id": $0.id, "type": $0.type] }
        )
        let legacyPayload = try uploadRecoveryObject(legacyResult.structuredContent)
        let legacyInspection = try uploadRecoveryValueObject(legacyPayload["inspection"])
        let legacyArguments = try uploadRecoveryValueObject(legacyInspection["arguments"])
        #expect(legacyArguments == ["parent_id": .string("parent-1")])
        #expect(legacyPayload["reservationFingerprint"] == nil)
        #expect(legacyInspection["continue_with_next_url"] == nil)
        #expect(legacyInspection["next_url_argument"] == nil)
        #expect(legacyInspection["candidate_match"] == nil)
    }

    @Test("cleanup guidance includes the exact destructive confirmation argument")
    func cleanupGuidanceIncludesConfirmationArgument() throws {
        let resource = UploadRecoveryProbeResource(type: "probeResources", id: "probe-1")
        let descriptor = UploadRecoveryDescriptor(
            resourceName: "probe",
            successKey: "resource",
            idArgument: "resource_id",
            getTool: "probe_get",
            getIDArgument: "resource_id",
            deleteTool: "probe_delete",
            deleteConfirmationArgument: "confirm_resource_id",
            inspectionTool: "probe_list",
            inspectionArguments: [:]
        )

        let failedCleanup = UploadTransactionRecovery.result(
            for: UploadTransactionOutcome<UploadRecoveryProbeResource>.preCommitFailure(
                "Upload failed",
                resource,
                .failed("Delete was rejected"),
                checksumReceipt: nil
            ),
            descriptor: descriptor,
            format: { ["id": $0.id, "type": $0.type] }
        )
        let failedPayload = try uploadRecoveryObject(failedCleanup.structuredContent)
        let failedGuidance = try uploadRecoveryValueObject(failedPayload["cleanup"])
        let failedArguments = try uploadRecoveryValueObject(failedGuidance["arguments"])
        #expect(failedArguments["resource_id"] == .string("probe-1"))
        #expect(failedArguments["confirm_resource_id"] == .string("probe-1"))
        #expect(uploadRecoveryText(failedCleanup).contains("confirm_resource_id 'probe-1'"))

        let retained = UploadTransactionRecovery.result(
            for: UploadTransactionOutcome<UploadRecoveryProbeResource>.processingPending(
                "Processing is pending",
                resource,
                reconciledAfterCommit: false
            ),
            descriptor: descriptor,
            format: { ["id": $0.id, "type": $0.type] }
        )
        let retainedPayload = try uploadRecoveryObject(retained.structuredContent)
        let retainedGuidance = try uploadRecoveryValueObject(retainedPayload["cleanup"])
        let retainedArguments = try uploadRecoveryValueObject(retainedGuidance["arguments"])
        #expect(retainedArguments["resource_id"] == .string("probe-1"))
        #expect(retainedArguments["confirm_resource_id"] == .string("probe-1"))
    }

    @Test("additional success metadata cannot override recovery state and remains redacted")
    func additionalSuccessMetadataIsBounded() throws {
        let resource = UploadRecoveryProbeResource(type: "probeResources", id: "probe-1")
        let result = UploadTransactionRecovery.result(
            for: UploadTransactionOutcome<UploadRecoveryProbeResource>.success(
                resource,
                reconciledAfterCommit: false
            ),
            descriptor: UploadRecoveryDescriptor(
                resourceName: "probe",
                successKey: "resource",
                idArgument: "resource_id",
                getTool: "probe_get",
                getIDArgument: "resource_id",
                deleteTool: "probe_delete",
                inspectionTool: "probe_list",
                inspectionArguments: [:]
            ),
            additionalSuccessFields: [
                "success": false,
                "resource": ["id": "forged"],
                "retrySafe": true,
                "operationCommitState": "committed_unverified",
                "resourceId": "forged",
                "resource_id": "forged",
                "deprecated": true,
                "providerStatus": "opaque_abcdefghijklmnopqrstuvwxyz012345"
            ],
            format: { ["id": $0.id, "type": $0.type] }
        )

        #expect(result.isError != true)
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["success"] == .bool(true))
        #expect(payload["retrySafe"] == nil)
        #expect(payload["operationCommitState"] == nil)
        #expect(payload["resourceId"] == nil)
        #expect(payload["resource_id"] == nil)
        #expect(payload["deprecated"] == .bool(true))
        #expect(payload["providerStatus"] == .string("[REDACTED]"))
        let formatted = try uploadRecoveryValueObject(payload["resource"])
        #expect(formatted["id"] == .string("probe-1"))
    }

    @Test("unexpected successful reservation status is committed and unverified", arguments: [200, 202, 204])
    func unexpectedReservationStatusIsNotOrdinarySuccess(_ statusCode: Int) async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: statusCode,
                body: uploadRecoveryResponse(
                    flow: flow,
                    state: flow.pendingState,
                    includeUploadOperation: true
                )
            )
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST"])
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["statusCode"] == .int(statusCode))
        #expect(payload["reservationState"] == .string("committed_unverified"))
        #expect(payload["reservationIdKnown"] == .bool(false))
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["operationCommitted"] == .bool(true))
        #expect(payload["outcomeUnknown"] == .bool(false))
        #expect(payload["inspectionRequired"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
    }

    @Test("deterministic reservation 4xx is rejected before creation")
    func deterministicReservationRejectionIsNotAmbiguous() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 422, body: uploadRecoveryAPIError(status: 422))
        ])

        let result = try await invokeUpload(
            .screenshot,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST"])
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["reservationState"] == .string("rejected"))
        #expect(payload["reservationCreated"] == .bool(false))
        #expect(payload["outcomeUnknown"] == nil)
        #expect(payload["operationCommitted"] == nil)
        #expect(payload["retrySafe"] == .bool(true))
    }

    @Test("unexpected successful commit status is committed and unverified", arguments: [201, 202, 204])
    func unexpectedCommitStatusIsNotOrdinarySuccess(_ statusCode: Int) async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                includeUploadOperation: true
            )),
            .init(statusCode: statusCode, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.completedState,
                includeChecksum: true
            ))
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        )

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH"])
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["statusCode"] == .int(statusCode))
        #expect(payload["resourceId"] == .string("asset-1"))
        #expect(payload["uploadCommitted"] == .bool(true))
        #expect(payload["processingComplete"] == .bool(false))
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["operationCommitted"] == .bool(true))
        #expect(payload["outcomeUnknown"] == .bool(false))
        #expect(payload["inspectionRequired"] == .bool(true))
        #expect(payload["reservationDeleted"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
    }

    @Test("missing upload operations roll back every resource family", arguments: [
        UploadFlow.screenshot,
        UploadFlow.preview,
        UploadFlow.iapImage,
        UploadFlow.iapVersionImage,
        UploadFlow.iapReviewScreenshot,
        UploadFlow.subscriptionImage,
        UploadFlow.subscriptionVersionImage,
        UploadFlow.subscriptionReviewScreenshot
    ])
    func missingOperationsRollBack(_ flow: UploadFlow) async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                fileName: fileURL.lastPathComponent
            )),
            .init(statusCode: 204, body: "")
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "DELETE"])
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["reservationDeleted"] == .bool(true))
        let cleanup = try uploadRecoveryValueObject(payload["cleanup"])
        #expect(cleanup["status"] == .string("deleted"))
    }

    @Test("lost PATCH reconciles with GET for every resource family", arguments: [
        UploadFlow.screenshot,
        UploadFlow.preview,
        UploadFlow.iapImage,
        UploadFlow.iapVersionImage,
        UploadFlow.iapReviewScreenshot,
        UploadFlow.subscriptionImage,
        UploadFlow.subscriptionVersionImage,
        UploadFlow.subscriptionReviewScreenshot
    ])
    func lostPatchReconciles(_ flow: UploadFlow) async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = UploadRecoveryScriptTransport(steps: [
            .response(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                fileName: fileURL.lastPathComponent,
                includeUploadOperation: true
            )),
            .rawNetworkFailure,
            .response(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.completedState,
                fileName: fileURL.lastPathComponent,
                includeChecksum: true
            ))
        ])
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH", "GET"])
        #expect(requests.map { $0.url?.path } == [
            flow.reservationPath,
            flow.resourcePath,
            flow.resourcePath
        ])
        #expect(requests.contains { $0.httpMethod == "DELETE" } == false)
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["reconciledAfterCommit"] == .bool(true))
    }

    @Test("failed processing after a lost PATCH remains an error", arguments: [
        UploadFlow.screenshot,
        UploadFlow.preview,
        UploadFlow.iapImage,
        UploadFlow.iapVersionImage,
        UploadFlow.iapReviewScreenshot,
        UploadFlow.subscriptionImage,
        UploadFlow.subscriptionVersionImage,
        UploadFlow.subscriptionReviewScreenshot
    ])
    func failedStateAfterLostPatchIsNotSuccess(_ flow: UploadFlow) async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = UploadRecoveryScriptTransport(steps: [
            .response(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                fileName: fileURL.lastPathComponent,
                includeUploadOperation: true
            )),
            .rawNetworkFailure,
            .response(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "FAILED",
                fileName: fileURL.lastPathComponent,
                includeChecksum: true
            ))
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        )

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH", "GET"])
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["deliveryPending"] == .bool(false))
        #expect(payload["reservationDeleted"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
    }

    @Test("ambiguous PATCH with only a pending GET remains unresolved")
    func ambiguousPatchWithPendingGetRemainsError() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let apiTransport = UploadRecoveryScriptTransport(steps: [
            .response(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                includeUploadOperation: true
            )),
            .rawNetworkFailure,
            .response(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "UPLOAD_COMPLETE",
                includeChecksum: true
            ))
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        )

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH", "GET"])
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["deliveryPending"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(payload["reservationDeleted"] == .bool(false))
    }

    @Test("confirmed 2xx with unreadable body and failed GET remains accepted pending")
    func confirmedMalformedCommitWithFailedGetIsAcceptedPending() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let apiTransport = UploadRecoveryScriptTransport(steps: [
            .response(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                includeUploadOperation: true
            )),
            .response(statusCode: 200, body: "{"),
            .failure("GET unavailable")
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        )

        #expect(result.isError != true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH", "GET"])
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["success"] == .bool(true))
        #expect(payload["uploadCommitted"] == .bool(true))
        #expect(payload["processingComplete"] == .bool(false))
        #expect(payload["deliveryPending"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
    }

    @Test("wrong commit resource reconciles the expected resource once")
    func wrongCommitResourceReconcilesExpectedResource() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                includeUploadOperation: true
            )),
            .init(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "COMPLETE",
                type: "appPreviews",
                includeChecksum: true
            )),
            .init(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "COMPLETE",
                includeChecksum: true
            ))
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        )

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH", "GET"])
        #expect(requests.contains { $0.httpMethod == "DELETE" } == false)
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["success"] == .bool(true))
        #expect(payload["reconciledAfterCommit"] == .bool(true))
    }

    @Test("wrong reconciliation resource is retained as an error")
    func wrongReconciliationResourceRemainsError() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                includeUploadOperation: true
            )),
            .init(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "COMPLETE",
                type: "appPreviews",
                includeChecksum: true
            )),
            .init(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "COMPLETE",
                type: "appPreviews",
                includeChecksum: true
            ))
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        )

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH", "GET"])
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["retrySafe"] == .bool(false))
        #expect(payload["reservationDeleted"] == .bool(false))
    }

    @Test("preview PROCESSING is polled to COMPLETE")
    func previewProcessingPollsToComplete() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.preview
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                includeUploadOperation: true
            )),
            .init(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "PROCESSING",
                includeChecksum: true
            )),
            .init(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "COMPLETE",
                includeChecksum: true
            ))
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        )

        #expect(result.isError != true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH", "GET"])
    }

    @Test("legacy UPLOAD_COMPLETE polls and REJECTED confirms upload processing", arguments: [
        UploadFlow.iapImage,
        UploadFlow.subscriptionImage
    ])
    func legacyUploadCompletePollsToBusinessState(_ flow: UploadFlow) async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                includeUploadOperation: true
            )),
            .init(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "UPLOAD_COMPLETE",
                includeChecksum: true
            )),
            .init(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "REJECTED",
                includeChecksum: true
            ))
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        )

        #expect(result.isError != true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH", "GET"])
    }

    @Test("confirmed commit with pending processing is accepted without retry")
    func confirmedPendingProcessingIsAccepted() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                includeUploadOperation: true
            )),
            .init(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "UPLOAD_COMPLETE",
                includeChecksum: true
            )),
            .init(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "UPLOAD_COMPLETE",
                includeChecksum: true
            ))
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        )

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH", "GET"])
        #expect(requests.contains { $0.httpMethod == "DELETE" } == false)
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["success"] == .bool(true))
        #expect(payload["uploadCommitted"] == .bool(true))
        #expect(payload["processingComplete"] == .bool(false))
        #expect(payload["deliveryPending"] == .bool(true))
        #expect(payload["reservationDeleted"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(payload["screenshot_id"] == .string("asset-1"))
    }

    @Test("ambiguous rollback preserves id and requires inspection")
    func ambiguousRollbackPreservesCleanupContext() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let resourceID = "asset-0123456789abcdef0123456789"
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                id: resourceID
            )),
            .init(statusCode: 500, body: uploadRecoveryAPIError(status: 500))
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        #expect(result.isError == true)
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["resourceId"] == .string(resourceID))
        #expect(payload["screenshot_id"] == .string(resourceID))
        #expect(payload["reservationDeleted"] == .bool(false))
        #expect(payload["operationCommitState"] == .string("unknown"))
        #expect(payload["outcomeUnknown"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
        let cleanup = try uploadRecoveryValueObject(payload["cleanup"])
        #expect(cleanup["status"] == .string("commit_unknown"))
        #expect(cleanup["operationCommitState"] == .string("unknown"))
        #expect(cleanup["outcomeUnknown"] == .bool(true))
        #expect(cleanup["retrySafe"] == .bool(false))
        #expect(cleanup["tool"] == nil)
        #expect(cleanup["arguments"] == nil)
        #expect(cleanup["inspectTool"] == .string("screenshots_get"))
        let inspectArguments = try uploadRecoveryValueObject(cleanup["inspectArguments"])
        #expect(inspectArguments["screenshot_id"] == .string(resourceID))
        guard case .text(let humanText, _, _) = result.content.first else {
            Issue.record("Expected human-readable recovery guidance")
            return
        }
        #expect(humanText.contains(resourceID))
        #expect(humanText.contains("Inspect the exact reservation"))
        #expect(humanText.contains("to retry cleanup") == false)
    }

    @Test("network loss during rollback is commit unknown")
    func networkLossDuringRollbackIsCommitUnknown() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let apiTransport = UploadRecoveryScriptTransport(steps: [
            .response(statusCode: 201, body: uploadRecoveryResponse(flow: flow, state: flow.pendingState)),
            .rawNetworkFailure
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["operationCommitState"] == .string("unknown"))
        #expect(payload["outcomeUnknown"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
        let cleanup = try uploadRecoveryValueObject(payload["cleanup"])
        #expect(cleanup["status"] == .string("commit_unknown"))
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "DELETE"])
    }

    @Test("unexpected successful rollback requires exact inspection", arguments: [200, 202])
    func unexpectedSuccessfulRollbackRequiresExactInspection(_ statusCode: Int) async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let resourceID = "asset-0123456789abcdef0123456789"
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                id: resourceID
            )),
            .init(statusCode: statusCode, body: "")
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "DELETE"])
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["reservationDeleted"] == .bool(false))
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["operationCommitted"] == .bool(true))
        #expect(payload["inspectionRequired"] == .bool(true))
        #expect(payload["outcomeUnknown"] == nil)
        #expect(payload["retrySafe"] == .bool(false))
        let cleanup = try uploadRecoveryValueObject(payload["cleanup"])
        #expect(cleanup["status"] == .string("committed_unverified"))
        #expect(cleanup["statusCode"] == .int(statusCode))
        #expect(cleanup["operationCommitState"] == .string("committed_unverified"))
        #expect(cleanup["operationCommitted"] == .bool(true))
        #expect(cleanup["inspectionRequired"] == .bool(true))
        #expect(cleanup["retrySafe"] == .bool(false))
        #expect(cleanup["tool"] == nil)
        #expect(cleanup["arguments"] == nil)
        #expect(cleanup["inspectTool"] == .string("screenshots_get"))
        let inspectArguments = try uploadRecoveryValueObject(cleanup["inspectArguments"])
        #expect(inspectArguments["screenshot_id"] == .string(resourceID))
        let text = uploadRecoveryText(result)
        #expect(text.contains("Inspect the exact reservation"))
        #expect(text.contains("to retry cleanup") == false)
    }

    @Test("definite rollback rejection remains a failed cleanup")
    func definiteRollbackRejectionRemainsFailedCleanup() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(flow: flow, state: flow.pendingState)),
            .init(statusCode: 403, body: uploadRecoveryAPIError(status: 403))
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["outcomeUnknown"] == nil)
        #expect(payload["retrySafe"] == .bool(false))
        let cleanup = try uploadRecoveryValueObject(payload["cleanup"])
        #expect(cleanup["status"] == .string("failed"))
        #expect(cleanup["outcomeUnknown"] == nil)
        #expect(cleanup["tool"] == .string("screenshots_delete"))
        #expect(uploadRecoveryText(result).contains("to retry cleanup"))
    }

    @Test("rollback 404 is treated as an already absent reservation")
    func rollbackNotFoundIsAlreadyAbsent() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(flow: flow, state: flow.pendingState)),
            .init(statusCode: 404, body: uploadRecoveryAPIError(status: 404))
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        #expect(result.isError == true)
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["reservationDeleted"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(true))
        let cleanup = try uploadRecoveryValueObject(payload["cleanup"])
        #expect(cleanup["status"] == .string("already_absent"))
    }

    @Test("batch upload rolls back each failed reservation")
    func batchRollsBackEachReservation() async throws {
        let firstURL = try uploadRecoveryFile(Data("first".utf8))
        let secondURL = try uploadRecoveryFile(Data("other".utf8))
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        let flow = UploadFlow.screenshot
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(flow: flow, state: flow.pendingState, id: "asset-1")),
            .init(statusCode: 204, body: ""),
            .init(statusCode: 201, body: uploadRecoveryResponse(flow: flow, state: flow.pendingState, id: "asset-2")),
            .init(statusCode: 204, body: "")
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: apiTransport,
            maxRetries: 1
        )
        let worker = ScreenshotsWorker(
            httpClient: client,
            uploadService: UploadService(transport: TestHTTPTransport(responses: []), batchSize: 1),
            deliveryPollAttempts: 1,
            deliveryPollIntervalNanoseconds: 0
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_upload_batch",
            arguments: [
                "set_id": .string("set-1"),
                "file_paths": .array([.string(firstURL.path), .string(secondURL.path)])
            ]
        ))

        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "DELETE", "POST", "DELETE"])
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["uploaded"] == .int(0))
        #expect(payload["failed"] == .int(2))
    }

    @Test("batch counts a committed processing-pending screenshot as uploaded")
    func batchCountsProcessingPendingAsUploaded() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                includeUploadOperation: true
            )),
            .init(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "UPLOAD_COMPLETE",
                includeChecksum: true
            )),
            .init(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "UPLOAD_COMPLETE",
                includeChecksum: true
            ))
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: apiTransport,
            maxRetries: 1
        )
        let worker = ScreenshotsWorker(
            httpClient: client,
            uploadService: UploadService(
                transport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")]),
                batchSize: 1
            ),
            deliveryPollAttempts: 1,
            deliveryPollIntervalNanoseconds: 0
        )

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_upload_batch",
            arguments: [
                "set_id": .string("set-1"),
                "file_paths": .array([.string(fileURL.path)])
            ]
        ))

        #expect(result.isError != true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "PATCH", "GET"])
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["uploaded"] == .int(1))
        #expect(payload["failed"] == .int(0))
        guard case .array(let results) = payload["results"],
              let first = results.first else {
            Issue.record("Expected one batch result")
            return
        }
        let item = try uploadRecoveryObject(first)
        #expect(item["success"] == .bool(true))
        #expect(item["upload_committed"] == .bool(true))
        #expect(item["delivery_pending"] == .bool(true))
        #expect(item["retry_safe"] == .bool(false))
    }

    @Test("ambiguous reservation response is not silently retried")
    func ambiguousReservationIsNotRetrySafe() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = UploadRecoveryScriptTransport(steps: [
            .rawNetworkFailure
        ])

        let result = try await invokeUpload(
            .screenshot,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST"])
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["reservationIdKnown"] == .bool(false))
        #expect(payload["reservationState"] == .string("unknown"))
        #expect(payload["operationCommitState"] == .string("unknown"))
        #expect(payload["operationCommitted"] == nil)
        #expect(payload["outcomeUnknown"] == .bool(true))
        #expect(payload["inspectionRequired"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(payload["sourceFileChecksumReceipt"] == nil)
        #expect(uploadRecoveryText(result).contains("checksum receipt") == false)
    }

    @Test("unreadable reservation response is not deleted or retried")
    func unreadableReservationIsNotRetrySafe() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: "{")
        ])

        let result = try await invokeUpload(
            .screenshot,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST"])
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["reservationIdKnown"] == .bool(false))
        #expect(payload["reservationState"] == .string("committed_unverified"))
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["operationCommitted"] == .bool(true))
        #expect(payload["outcomeUnknown"] == .bool(false))
        #expect(payload["inspectionRequired"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
    }

    @Test("source mutation after reservation starts cannot change uploaded snapshot")
    func snapshotIsPreparedBeforeReservation() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = UploadRecoveryMutationTransport(fileURL: fileURL)
        let uploadTransport = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])

        let result = try await invokeUpload(
            .screenshot,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        #expect(result.isError != true)
        let uploadRequest = try #require(await uploadTransport.recordedRequests().first)
        #expect(uploadRequest.httpBody == Data("hello".utf8))
        #expect(try Data(contentsOf: fileURL) == Data("changed after reservation".utf8))
        let reserveRequest = try #require(await apiTransport.recordedRequests().first)
        let body = try uploadRecoveryJSONBody(reserveRequest)
        let data = try uploadRecoveryDictionary(body["data"])
        let attributes = try uploadRecoveryDictionary(data["attributes"])
        #expect(attributes["fileSize"] as? Int == 5)
    }

    @Test("cancellation before reservation never sends POST")
    func cancellationBeforeReservationDoesNotCreateResource() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [])

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await invokeUpload(
                .screenshot,
                fileURL: fileURL,
                apiTransport: apiTransport,
                uploadTransport: TestHTTPTransport(responses: [])
            )
        }
        let result = try await task.value

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().isEmpty)
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["reservationCreated"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(true))
    }

    @Test("cancellation after a confirmed reservation rolls it back before PATCH")
    func cancellationAfterReservationRollsBack() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let apiTransport = UploadRecoveryScriptTransport(steps: [
            .cancelAndResponse(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                includeUploadOperation: true
            )),
            .response(statusCode: 204, body: "")
        ])
        let uploadTransport = TestHTTPTransport(responses: [])

        let task = Task {
            try await invokeUpload(
                flow,
                fileURL: fileURL,
                apiTransport: apiTransport,
                uploadTransport: uploadTransport
            )
        }
        let result = try await task.value

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST", "DELETE"])
        #expect(await uploadTransport.recordedRequests().isEmpty)
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["reservationDeleted"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(true))
    }

    @Test("cancellation once PATCH may have started retains the resource")
    func cancellationAfterPatchStartsNeverDeletes() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let apiTransport = UploadRecoveryScriptTransport(steps: [
            .response(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                includeUploadOperation: true
            )),
            .cancelAndResponse(statusCode: 200, body: uploadRecoveryResponse(
                flow: flow,
                state: "UPLOAD_COMPLETE",
                includeChecksum: true
            ))
        ])

        let task = Task {
            try await invokeUpload(
                flow,
                fileURL: fileURL,
                apiTransport: apiTransport,
                uploadTransport: TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
            )
        }
        let result = try await task.value

        #expect(result.isError != true)
        let requests = await apiTransport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH"])
        #expect(requests.contains { $0.httpMethod == "DELETE" } == false)
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["success"] == .bool(true))
        #expect(payload["uploadCommitted"] == .bool(true))
        #expect(payload["processingComplete"] == .bool(false))
        #expect(payload["reservationDeleted"] == .bool(false))
        #expect(payload["deliveryPending"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
    }

    @Test("unexpected reservation type is retained without deleting an unconfirmed identity")
    func wrongReservationTypeIsNotDeleted() async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let flow = UploadFlow.screenshot
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                type: "appPreviews"
            ))
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: TestHTTPTransport(responses: [])
        )

        #expect(result.isError == true)
        #expect(await apiTransport.recordedRequests().map(\.httpMethod) == ["POST"])
        let payload = try uploadRecoveryObject(result.structuredContent)
        #expect(payload["reservationIdKnown"] == .bool(false))
        #expect(payload["reservationState"] == .string("committed_unverified"))
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["operationCommitted"] == .bool(true))
        #expect(payload["outcomeUnknown"] == .bool(false))
        #expect(payload["inspectionRequired"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(false))
    }

    @Test("transfer errors never expose presigned URLs or secret upload headers", arguments: [
        UploadFlow.screenshot,
        UploadFlow.preview,
        UploadFlow.iapImage,
        UploadFlow.iapVersionImage,
        UploadFlow.iapReviewScreenshot,
        UploadFlow.subscriptionImage,
        UploadFlow.subscriptionVersionImage,
        UploadFlow.subscriptionReviewScreenshot
    ])
    func transferErrorsDoNotExposeUploadCredentials(_ flow: UploadFlow) async throws {
        let fileURL = try uploadRecoveryFile(Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: uploadRecoveryResponse(
                flow: flow,
                state: flow.pendingState,
                includeUploadOperation: true,
                includeSecretHeader: true
            )),
            .init(statusCode: 204, body: "")
        ])

        let result = try await invokeUpload(
            flow,
            fileURL: fileURL,
            apiTransport: apiTransport,
            uploadTransport: LeakingUploadTransport()
        )

        #expect(result.isError == true)
        let text = uploadRecoveryText(result)
        #expect(uploadRecoveryContains(result.structuredContent, substring: "upload.example.test") == false)
        #expect(uploadRecoveryContains(result.structuredContent, substring: "signed-secret") == false)
        #expect(uploadRecoveryContains(result.structuredContent, substring: "header-secret") == false)
        #expect(text.contains("upload.example.test") == false)
        #expect(text.contains("signed-secret") == false)
        #expect(text.contains("header-secret") == false)
    }
}

enum UploadFlow: String, Sendable {
    case screenshot
    case preview
    case iapImage
    case iapVersionImage
    case iapReviewScreenshot
    case subscriptionImage
    case subscriptionVersionImage
    case subscriptionReviewScreenshot

    var type: String {
        switch self {
        case .screenshot: return "appScreenshots"
        case .preview: return "appPreviews"
        case .iapImage, .iapVersionImage: return "inAppPurchaseImages"
        case .iapReviewScreenshot: return "inAppPurchaseAppStoreReviewScreenshots"
        case .subscriptionImage, .subscriptionVersionImage: return "subscriptionImages"
        case .subscriptionReviewScreenshot: return "subscriptionAppStoreReviewScreenshots"
        }
    }

    var reservationPath: String {
        switch self {
        case .screenshot: return "/v1/appScreenshots"
        case .preview: return "/v1/appPreviews"
        case .iapImage: return "/v1/inAppPurchaseImages"
        case .iapVersionImage: return "/v2/inAppPurchaseImages"
        case .iapReviewScreenshot: return "/v1/inAppPurchaseAppStoreReviewScreenshots"
        case .subscriptionImage: return "/v1/subscriptionImages"
        case .subscriptionVersionImage: return "/v2/subscriptionImages"
        case .subscriptionReviewScreenshot: return "/v1/subscriptionAppStoreReviewScreenshots"
        }
    }

    var resourcePath: String { "\(reservationPath)/asset-1" }

    var pendingState: String { "AWAITING_UPLOAD" }

    var completedState: String {
        switch self {
        case .iapImage, .subscriptionImage:
            return "PREPARE_FOR_SUBMISSION"
        default:
            return "COMPLETE"
        }
    }

    var usesLegacyState: Bool {
        self == .iapImage || self == .subscriptionImage
    }
}

private func invokeUpload(
    _ flow: UploadFlow,
    fileURL: URL,
    apiTransport: any HTTPTransport,
    uploadTransport: any HTTPTransport,
    pollAttempts: Int = 1
) async throws -> CallTool.Result {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: apiTransport,
        maxRetries: 3
    )
    let uploadService = UploadService(transport: uploadTransport, batchSize: 1)

    switch flow {
    case .screenshot:
        let worker = ScreenshotsWorker(
            httpClient: client,
            uploadService: uploadService,
            deliveryPollAttempts: pollAttempts,
            deliveryPollIntervalNanoseconds: 0
        )
        return try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_upload",
            arguments: ["set_id": .string("set-1"), "file_path": .string(fileURL.path)]
        ))

    case .preview:
        let worker = ScreenshotsWorker(
            httpClient: client,
            uploadService: uploadService,
            deliveryPollAttempts: pollAttempts,
            deliveryPollIntervalNanoseconds: 0
        )
        return try await worker.handleTool(CallTool.Parameters(
            name: "screenshots_upload_preview",
            arguments: ["set_id": .string("set-1"), "file_path": .string(fileURL.path)]
        ))

    case .iapImage:
        let worker = InAppPurchasesWorker(
            httpClient: client,
            uploadService: uploadService,
            deliveryPollAttempts: pollAttempts,
            deliveryPollIntervalNanoseconds: 0
        )
        return try await worker.handleTool(CallTool.Parameters(
            name: "iap_upload_image",
            arguments: ["iap_id": .string("iap-1"), "file_path": .string(fileURL.path)]
        ))

    case .iapVersionImage:
        let worker = InAppPurchasesWorker(
            httpClient: client,
            uploadService: uploadService,
            deliveryPollAttempts: pollAttempts,
            deliveryPollIntervalNanoseconds: 0
        )
        return try await worker.handleTool(CallTool.Parameters(
            name: "iap_upload_version_image",
            arguments: ["version_id": .string("iap-version-1"), "file_path": .string(fileURL.path)]
        ))

    case .iapReviewScreenshot:
        let worker = InAppPurchasesWorker(
            httpClient: client,
            uploadService: uploadService,
            deliveryPollAttempts: pollAttempts,
            deliveryPollIntervalNanoseconds: 0
        )
        return try await worker.handleTool(CallTool.Parameters(
            name: "iap_upload_review_screenshot",
            arguments: ["iap_id": .string("iap-1"), "file_path": .string(fileURL.path)]
        ))

    case .subscriptionImage:
        let worker = SubscriptionsWorker(
            httpClient: client,
            uploadService: uploadService,
            deliveryPollAttempts: pollAttempts,
            deliveryPollIntervalNanoseconds: 0
        )
        return try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_upload_image",
            arguments: ["subscription_id": .string("subscription-1"), "file_path": .string(fileURL.path)]
        ))

    case .subscriptionVersionImage:
        let worker = SubscriptionsWorker(
            httpClient: client,
            uploadService: uploadService,
            deliveryPollAttempts: pollAttempts,
            deliveryPollIntervalNanoseconds: 0
        )
        return try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_upload_version_image",
            arguments: ["version_id": .string("subscription-version-1"), "file_path": .string(fileURL.path)]
        ))

    case .subscriptionReviewScreenshot:
        let worker = SubscriptionsWorker(
            httpClient: client,
            uploadService: uploadService,
            deliveryPollAttempts: pollAttempts,
            deliveryPollIntervalNanoseconds: 0
        )
        return try await worker.handleTool(CallTool.Parameters(
            name: "subscriptions_upload_review_screenshot",
            arguments: ["subscription_id": .string("subscription-1"), "file_path": .string(fileURL.path)]
        ))
    }
}

private func performProbeReservation(
    fileURL: URL,
    apiTransport: any HTTPTransport
) async throws -> UploadTransactionOutcome<UploadRecoveryProbeResource> {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: apiTransport,
        maxRetries: 3
    )
    return await UploadTransactionRecovery.perform(
        filePath: fileURL.path,
        resourceName: "probe",
        expectedType: "probeResources",
        reservationEndpoint: "/v1/probeResources",
        httpClient: client,
        uploadService: UploadService(
            transport: TestHTTPTransport(responses: []),
            batchSize: 1
        ),
        deliveryPollAttempts: 0,
        deliveryPollIntervalNanoseconds: 0,
        makeReservationBody: { _, _ in Data() },
        decodeResource: { _ in
            UploadRecoveryProbeResource(type: "probeResources", id: "probe-1")
        },
        makeCommitBody: { _, _ in Data() },
        resourceEndpoint: {
            "/v1/probeResources/\(try ASCPathSegment.encode($0))"
        }
    )
}

private func uploadRecoveryResponse(
    flow: UploadFlow,
    state: String,
    id: String = "asset-1",
    type: String? = nil,
    fileName: String = "asset.bin",
    includeUploadOperation: Bool = false,
    includeSecretHeader: Bool = false,
    includeChecksum: Bool = false
) -> String {
    let stateFragment: String
    if flow.usesLegacyState {
        stateFragment = #", "state":"\#(state)""#
    } else if flow == .preview {
        stateFragment = #", "videoDeliveryState":{"state":"\#(state)"}"#
    } else {
        stateFragment = #", "assetDeliveryState":{"state":"\#(state)"}"#
    }
    let checksumFragment = includeChecksum
        ? #", "sourceFileChecksum":"5d41402abc4b2a76b9719d911017c592""#
        : ""
    let requestHeaders = includeSecretHeader
        ? #"[{"name":"X-Amz-Security-Token","value":"header-secret"}]"#
        : "[]"
    let operationsFragment = includeUploadOperation
        ? #", "uploadOperations":[{"method":"PUT","url":"https://upload.example.test/chunk?signed=signed-secret","length":5,"offset":0,"requestHeaders":\#(requestHeaders)}]"#
        : ""
    return #"{"data":{"type":"\#(type ?? flow.type)","id":"\#(id)","attributes":{"fileSize":5,"fileName":"\#(fileName)"\#(checksumFragment)\#(stateFragment)\#(operationsFragment)}},"links":{"self":"\#(flow.reservationPath)/\#(id)"}}"#
}

private func uploadRecoveryFile(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("asc-mcp-upload-recovery-\(UUID().uuidString).bin")
    try data.write(to: url)
    return url
}

private func uploadRecoveryAPIError(status: Int) -> String {
    #"{"errors":[{"status":"\#(status)","code":"UNEXPECTED_ERROR","title":"Request failed","detail":"Request failed"}]}"#
}

private func uploadRecoveryObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected structured object")
        throw UploadRecoveryTestFailure.expectedObject
    }
    return object
}

private func uploadRecoveryValueObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected nested structured object")
        throw UploadRecoveryTestFailure.expectedObject
    }
    return object
}

private func uploadRecoveryJSONBody(_ request: URLRequest) throws -> [String: Any] {
    guard let body = request.httpBody,
          let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        throw UploadRecoveryTestFailure.expectedDictionary
    }
    return object
}

private func uploadRecoveryDictionary(_ value: Any?) throws -> [String: Any] {
    guard let dictionary = value as? [String: Any] else {
        throw UploadRecoveryTestFailure.expectedDictionary
    }
    return dictionary
}

private func uploadRecoveryContains(_ value: Value?, substring: String) -> Bool {
    guard let value else { return false }
    switch value {
    case .string(let string):
        return string.contains(substring)
    case .array(let values):
        return values.contains { uploadRecoveryContains($0, substring: substring) }
    case .object(let object):
        return object.contains { key, value in
            key.contains(substring) || uploadRecoveryContains(value, substring: substring)
        }
    default:
        return false
    }
}

private func uploadRecoveryText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content {
            return text
        }
        return nil
    }.joined(separator: "\n")
}

private enum UploadRecoveryTestFailure: Error {
    case expectedObject
    case expectedDictionary
}

private struct UploadRecoveryProbeResource: RecoverableUploadResource {
    let type: String
    let id: String

    var recoveryUploadOperations: [ASCUploadOperation]? { nil }
    var recoveryDeliveryStatus: UploadDeliveryStatus { .complete("COMPLETE") }
}

private actor UploadRecoveryScriptTransport: HTTPTransport {
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
                uploadRecoveryHTTPResponse(request: request, statusCode: statusCode)
            )
        case .cancelAndResponse(let statusCode, let body):
            withUnsafeCurrentTask { $0?.cancel() }
            return (
                Data(body.utf8),
                uploadRecoveryHTTPResponse(request: request, statusCode: statusCode)
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

private actor LeakingUploadTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw ASCError.network("LeakingUploadTransport only supports file uploads")
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        let url = request.url?.absoluteString ?? "missing-url"
        let headers = request.allHTTPHeaderFields ?? [:]
        throw ASCError.network("Transfer failed for \(url) with headers \(headers)")
    }
}

private actor UploadRecoveryMutationTransport: HTTPTransport {
    private let fileURL: URL
    private var requests: [URLRequest] = []

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        switch request.httpMethod {
        case "POST":
            try Data("changed after reservation".utf8).write(to: fileURL)
            return (
                Data(uploadRecoveryResponse(
                    flow: .screenshot,
                    state: "AWAITING_UPLOAD",
                    includeUploadOperation: true
                ).utf8),
                uploadRecoveryHTTPResponse(request: request, statusCode: 201)
            )
        case "PATCH":
            return (
                Data(uploadRecoveryResponse(
                    flow: .screenshot,
                    state: "COMPLETE",
                    includeChecksum: true
                ).utf8),
                uploadRecoveryHTTPResponse(request: request, statusCode: 200)
            )
        default:
            throw ASCError.network("Unexpected request")
        }
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private func uploadRecoveryHTTPResponse(request: URLRequest, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url ?? URL(string: "https://api.example.test")!,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: [:]
    )!
}
