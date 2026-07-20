import Foundation
import MCP

struct UploadRecoveryDescriptor: Sendable {
    let resourceName: String
    let successKey: String
    let idArgument: String
    let getTool: String?
    let getIDArgument: String?
    let deleteTool: String?
    let inspectionTool: String
    let inspectionArguments: [String: String]
    let checksumReceiptKey: String?

    init(
        resourceName: String,
        successKey: String,
        idArgument: String,
        getTool: String?,
        getIDArgument: String?,
        deleteTool: String?,
        inspectionTool: String,
        inspectionArguments: [String: String],
        checksumReceiptKey: String? = nil
    ) {
        self.resourceName = resourceName
        self.successKey = successKey
        self.idArgument = idArgument
        self.getTool = getTool
        self.getIDArgument = getIDArgument
        self.deleteTool = deleteTool
        self.inspectionTool = inspectionTool
        self.inspectionArguments = inspectionArguments
        self.checksumReceiptKey = checksumReceiptKey
    }
}

protocol RecoverableUploadResource: Sendable {
    var type: String { get }
    var id: String { get }
    var recoveryUploadOperations: [ASCUploadOperation]? { get }
    var recoveryDeliveryStatus: UploadDeliveryStatus { get }
}

enum UploadDeliveryStatus: Sendable {
    case pending(String?)
    case complete(String)
    case failed(String)
}

enum UploadTransactionOutcome<Resource: RecoverableUploadResource>: Sendable {
    case success(Resource, reconciledAfterCommit: Bool)
    case processingPending(String, Resource, reconciledAfterCommit: Bool)
    case beforeReservation(String)
    case reservationRejected(String)
    case reservationUnresolved(String, checksumReceipt: String?)
    case preCommitFailure(String, Resource, UploadCleanupOutcome, checksumReceipt: String?)
    case commitFailed(String, Resource)
    case commitUnresolved(String, Resource)
}

enum UploadCleanupOutcome: Sendable {
    case deleted
    case alreadyAbsent
    case unavailable(String)
    case commitUnknown(String)
    case committedUnverified(statusCode: Int, reason: String)
    case failed(String)

    var status: String {
        switch self {
        case .deleted:
            return "deleted"
        case .alreadyAbsent:
            return "already_absent"
        case .unavailable:
            return "unavailable"
        case .commitUnknown:
            return "commit_unknown"
        case .committedUnverified:
            return "committed_unverified"
        case .failed:
            return "failed"
        }
    }

    var reservationDeleted: Bool {
        switch self {
        case .deleted, .alreadyAbsent:
            return true
        case .unavailable, .commitUnknown, .committedUnverified, .failed:
            return false
        }
    }

    var outcomeUnknown: Bool {
        if case .commitUnknown = self {
            return true
        }
        return false
    }

    var completionUnverified: Bool {
        if case .committedUnverified = self {
            return true
        }
        return false
    }
}

enum UploadReservationCleanupPolicy: Sendable {
    case delete
    case retain(String)
}

enum UploadReservationFailureDisposition: Sendable, Equatable {
    case rejected
    case unresolved
}

enum UploadTransactionRecovery {
    static func perform<Resource: RecoverableUploadResource>(
        filePath: String,
        resourceName: String,
        expectedType: String,
        reservationEndpoint: String,
        httpClient: HTTPClient,
        uploadService: UploadService,
        cleanupPolicy: UploadReservationCleanupPolicy = .delete,
        existingResource: Resource? = nil,
        validateSnapshot: @Sendable (Resource?, UploadFileSnapshot) throws -> Void = { _, _ in },
        validateReservedResource: @Sendable (Resource, UploadFileSnapshot) throws -> Void = { _, _ in },
        reservationFailureDisposition: @Sendable (Error) -> UploadReservationFailureDisposition = { _ in .unresolved },
        deliveryPollAttempts: Int,
        deliveryPollIntervalNanoseconds: UInt64,
        makeReservationBody: @Sendable (Int, String) throws -> Data,
        decodeResource: @Sendable (Data) throws -> Resource,
        makeCommitBody: @Sendable (String, String) throws -> Data,
        resourceEndpoint: @Sendable (String) throws -> String
    ) async -> UploadTransactionOutcome<Resource> {
        let existingEndpoint: String?
        if let existingResource {
            guard !existingResource.id.isEmpty, existingResource.type == expectedType else {
                return .reservationUnresolved(
                    "The existing \(resourceName) reservation identity could not be confirmed.",
                    checksumReceipt: nil
                )
            }
            do {
                existingEndpoint = try resourceEndpoint(existingResource.id)
            } catch {
                return .reservationUnresolved(
                    "The existing \(resourceName) reservation has an invalid resource id.",
                    checksumReceipt: nil
                )
            }
        } else {
            existingEndpoint = nil
        }

        if Task.isCancelled {
            if let existingResource, let existingEndpoint {
                let cleanup = await rollbackReservation(
                    httpClient: httpClient,
                    endpoint: existingEndpoint,
                    policy: cleanupPolicy
                )
                return .preCommitFailure(
                    "The \(resourceName) upload was cancelled before transfer.",
                    existingResource,
                    cleanup,
                    checksumReceipt: nil
                )
            }
            return .beforeReservation("The \(resourceName) upload was cancelled before reservation.")
        }

        let snapshot: UploadFileSnapshot
        do {
            snapshot = try await uploadService.prepareSnapshot(filePath: filePath)
        } catch {
            if let existingResource, let existingEndpoint {
                let cleanup = await rollbackReservation(
                    httpClient: httpClient,
                    endpoint: existingEndpoint,
                    policy: cleanupPolicy
                )
                return .preCommitFailure(
                    "Failed to read \(resourceName): \(error.localizedDescription)",
                    existingResource,
                    cleanup,
                    checksumReceipt: nil
                )
            }
            return .beforeReservation("Failed to read \(resourceName): \(error.localizedDescription)")
        }
        defer { snapshot.discard() }

        if Task.isCancelled {
            if let existingResource, let existingEndpoint {
                let cleanup = await rollbackReservation(
                    httpClient: httpClient,
                    endpoint: existingEndpoint,
                    policy: cleanupPolicy
                )
                return .preCommitFailure(
                    "The \(resourceName) upload was cancelled before transfer.",
                    existingResource,
                    cleanup,
                    checksumReceipt: snapshot.md5Checksum
                )
            }
            return .beforeReservation("The \(resourceName) upload was cancelled before reservation.")
        }

        do {
            try validateSnapshot(existingResource, snapshot)
        } catch {
            if let existingResource, let existingEndpoint {
                let cleanup = await rollbackReservation(
                    httpClient: httpClient,
                    endpoint: existingEndpoint,
                    policy: cleanupPolicy
                )
                return .preCommitFailure(
                    "The \(resourceName) file does not match its reservation: \(error.localizedDescription)",
                    existingResource,
                    cleanup,
                    checksumReceipt: snapshot.md5Checksum
                )
            }
            return .beforeReservation(
                "The \(resourceName) file is invalid for reservation: \(error.localizedDescription)"
            )
        }

        let reserved: Resource
        let endpoint: String
        if let existingResource, let existingEndpoint {
            reserved = existingResource
            endpoint = existingEndpoint
        } else {
            let reservationBody: Data
            do {
                reservationBody = try makeReservationBody(snapshot.fileSize, snapshot.fileName)
            } catch {
                return .beforeReservation("Failed to prepare the \(resourceName) reservation: \(error.localizedDescription)")
            }

            let reservationData: Data
            do {
                reservationData = try await httpClient.post(reservationEndpoint, body: reservationBody)
            } catch {
                if reservationFailureDisposition(error) == .rejected {
                    return .reservationRejected(
                        "The \(resourceName) reservation was rejected before creation: \(error.localizedDescription)"
                    )
                }
                return .reservationUnresolved(
                    "The \(resourceName) reservation request did not return a confirmed response: \(error.localizedDescription)",
                    checksumReceipt: snapshot.md5Checksum
                )
            }

            do {
                reserved = try decodeResource(reservationData)
            } catch {
                return .reservationUnresolved(
                    "Apple returned an unreadable \(resourceName) reservation response: \(error.localizedDescription)",
                    checksumReceipt: snapshot.md5Checksum
                )
            }

            guard !reserved.id.isEmpty else {
                return .reservationUnresolved(
                    "Apple returned a \(resourceName) reservation without a usable resource id.",
                    checksumReceipt: snapshot.md5Checksum
                )
            }

            guard reserved.type == expectedType else {
                return .reservationUnresolved(
                    "Apple returned an unexpected resource type for the \(resourceName) reservation, so its identity could not be confirmed.",
                    checksumReceipt: snapshot.md5Checksum
                )
            }

            do {
                endpoint = try resourceEndpoint(reserved.id)
            } catch {
                return .reservationUnresolved(
                    "Apple returned a \(resourceName) reservation with an invalid resource id.",
                    checksumReceipt: snapshot.md5Checksum
                )
            }
        }

        do {
            try validateReservedResource(reserved, snapshot)
        } catch {
            let cleanup = await rollbackReservation(
                httpClient: httpClient,
                endpoint: endpoint,
                policy: cleanupPolicy
            )
            return .preCommitFailure(
                "The \(resourceName) reservation cannot accept a transfer: \(error.localizedDescription)",
                reserved,
                cleanup,
                checksumReceipt: snapshot.md5Checksum
            )
        }

        if Task.isCancelled {
            let cleanup = await rollbackReservation(
                httpClient: httpClient,
                endpoint: endpoint,
                policy: cleanupPolicy
            )
            return .preCommitFailure(
                "The \(resourceName) upload was cancelled after reservation and before commit.",
                reserved,
                cleanup,
                checksumReceipt: snapshot.md5Checksum
            )
        }

        guard let operations = reserved.recoveryUploadOperations, !operations.isEmpty else {
            let cleanup = await rollbackReservation(
                httpClient: httpClient,
                endpoint: endpoint,
                policy: cleanupPolicy
            )
            return .preCommitFailure(
                "Apple returned no upload operations for the \(resourceName) reservation.",
                reserved,
                cleanup,
                checksumReceipt: snapshot.md5Checksum
            )
        }

        let checksum: String
        do {
            checksum = try await uploadService.uploadFile(snapshot: snapshot, uploadOperations: operations)
        } catch {
            let cleanup = await rollbackReservation(
                httpClient: httpClient,
                endpoint: endpoint,
                policy: cleanupPolicy
            )
            return .preCommitFailure(
                "Failed to transfer \(resourceName) bytes through Apple's upload endpoint.",
                reserved,
                cleanup,
                checksumReceipt: snapshot.md5Checksum
            )
        }

        let commitBody: Data
        do {
            commitBody = try makeCommitBody(reserved.id, checksum)
        } catch {
            let cleanup = await rollbackReservation(
                httpClient: httpClient,
                endpoint: endpoint,
                policy: cleanupPolicy
            )
            return .preCommitFailure(
                "Failed to prepare the \(resourceName) commit: \(error.localizedDescription)",
                reserved,
                cleanup,
                checksumReceipt: snapshot.md5Checksum
            )
        }

        if Task.isCancelled {
            let cleanup = await rollbackReservation(
                httpClient: httpClient,
                endpoint: endpoint,
                policy: cleanupPolicy
            )
            return .preCommitFailure(
                "The \(resourceName) commit was not attempted because the operation was cancelled.",
                reserved,
                cleanup,
                checksumReceipt: snapshot.md5Checksum
            )
        }

        let commitData: Data
        do {
            commitData = try await httpClient.patch(endpoint, body: commitBody)
        } catch {
            let commitContext = "The \(resourceName) commit did not return a confirmed response: \(error.localizedDescription)"
            return await reconcileCommit(
                httpClient: httpClient,
                endpoint: endpoint,
                expectedID: reserved.id,
                expectedType: expectedType,
                lastKnown: reserved,
                context: commitContext,
                commitConfirmed: false,
                deliveryPollAttempts: deliveryPollAttempts,
                deliveryPollIntervalNanoseconds: deliveryPollIntervalNanoseconds,
                decodeResource: decodeResource
            )
        }

        let committed: Resource
        do {
            committed = try decodeResource(commitData)
        } catch {
            return await reconcileCommit(
                httpClient: httpClient,
                endpoint: endpoint,
                expectedID: reserved.id,
                expectedType: expectedType,
                lastKnown: reserved,
                context: "Apple accepted the \(resourceName) commit but returned an unreadable response: \(error.localizedDescription)",
                commitConfirmed: true,
                deliveryPollAttempts: deliveryPollAttempts,
                deliveryPollIntervalNanoseconds: deliveryPollIntervalNanoseconds,
                decodeResource: decodeResource
            )
        }

        guard committed.id == reserved.id, committed.type == expectedType else {
            return await reconcileUnexpectedCommitResource(
                httpClient: httpClient,
                endpoint: endpoint,
                expectedID: reserved.id,
                expectedType: expectedType,
                lastKnown: reserved,
                context: "Apple accepted the \(resourceName) commit but returned an unexpected resource.",
                decodeResource: decodeResource
            )
        }

        return await resolveDelivery(
            httpClient: httpClient,
            endpoint: endpoint,
            expectedID: reserved.id,
            expectedType: expectedType,
            latest: committed,
            context: nil,
            commitConfirmed: true,
            reconciledAfterCommit: false,
            deliveryPollAttempts: deliveryPollAttempts,
            deliveryPollIntervalNanoseconds: deliveryPollIntervalNanoseconds,
            decodeResource: decodeResource
        )
    }

    static func result<Resource: RecoverableUploadResource>(
        for outcome: UploadTransactionOutcome<Resource>,
        descriptor: UploadRecoveryDescriptor,
        format: (Resource) -> [String: Any]
    ) -> CallTool.Result {
        let payload = payload(for: outcome, descriptor: descriptor, format: format)
        return MCPResult.jsonObject(payload.value, text: payload.text, isError: payload.isError)
    }

    static func failurePayload<Resource: RecoverableUploadResource>(
        for outcome: UploadTransactionOutcome<Resource>,
        descriptor: UploadRecoveryDescriptor,
        format: (Resource) -> [String: Any]
    ) -> [String: Any]? {
        let payload = payload(for: outcome, descriptor: descriptor, format: format)
        return payload.isError ? payload.value : nil
    }

    private static func reconcileUnexpectedCommitResource<Resource: RecoverableUploadResource>(
        httpClient: HTTPClient,
        endpoint: String,
        expectedID: String,
        expectedType: String,
        lastKnown: Resource,
        context: String,
        decodeResource: @Sendable (Data) throws -> Resource
    ) async -> UploadTransactionOutcome<Resource> {
        if Task.isCancelled {
            return .commitUnresolved(context, lastKnown)
        }

        let data: Data
        do {
            data = try await httpClient.get(endpoint)
        } catch {
            return .commitUnresolved(
                "\(context) Reconciliation also failed: \(error.localizedDescription)",
                lastKnown
            )
        }

        let current: Resource
        do {
            current = try decodeResource(data)
        } catch {
            return .commitUnresolved(
                "\(context) Apple returned an unreadable reconciliation response: \(error.localizedDescription)",
                lastKnown
            )
        }

        guard current.id == expectedID, current.type == expectedType else {
            return .commitUnresolved(
                "\(context) Apple also returned an unexpected resource during reconciliation.",
                lastKnown
            )
        }

        switch current.recoveryDeliveryStatus {
        case .complete:
            return .success(current, reconciledAfterCommit: true)
        case .failed(let state):
            return .commitFailed(
                "\(context) Apple reports terminal upload state '\(state)' for the expected resource.",
                current
            )
        case .pending(let state):
            return .processingPending(
                "\(context) The expected resource was reconciled in state '\(state ?? "unknown")' and retained for processing.",
                current,
                reconciledAfterCommit: true
            )
        }
    }

    private static func reconcileCommit<Resource: RecoverableUploadResource>(
        httpClient: HTTPClient,
        endpoint: String,
        expectedID: String,
        expectedType: String,
        lastKnown: Resource,
        context: String,
        commitConfirmed: Bool,
        deliveryPollAttempts: Int,
        deliveryPollIntervalNanoseconds: UInt64,
        decodeResource: @Sendable (Data) throws -> Resource
    ) async -> UploadTransactionOutcome<Resource> {
        if Task.isCancelled {
            return pendingOrUnresolved(
                commitConfirmed: commitConfirmed,
                message: context,
                resource: lastKnown,
                reconciledAfterCommit: false
            )
        }

        let data: Data
        do {
            data = try await httpClient.get(endpoint)
        } catch {
            return pendingOrUnresolved(
                commitConfirmed: commitConfirmed,
                message: "\(context) Reconciliation also failed: \(error.localizedDescription)",
                resource: lastKnown,
                reconciledAfterCommit: true
            )
        }

        let current: Resource
        do {
            current = try decodeResource(data)
        } catch {
            return pendingOrUnresolved(
                commitConfirmed: commitConfirmed,
                message: "\(context) Apple returned an unreadable reconciliation response: \(error.localizedDescription)",
                resource: lastKnown,
                reconciledAfterCommit: true
            )
        }

        guard current.id == expectedID, current.type == expectedType else {
            return .commitUnresolved(
                "\(context) Apple returned an unexpected resource during reconciliation.",
                lastKnown
            )
        }

        return await resolveDelivery(
            httpClient: httpClient,
            endpoint: endpoint,
            expectedID: expectedID,
            expectedType: expectedType,
            latest: current,
            context: context,
            commitConfirmed: commitConfirmed,
            reconciledAfterCommit: true,
            deliveryPollAttempts: max(0, deliveryPollAttempts - 1),
            deliveryPollIntervalNanoseconds: deliveryPollIntervalNanoseconds,
            decodeResource: decodeResource
        )
    }

    private static func resolveDelivery<Resource: RecoverableUploadResource>(
        httpClient: HTTPClient,
        endpoint: String,
        expectedID: String,
        expectedType: String,
        latest: Resource,
        context: String?,
        commitConfirmed: Bool,
        reconciledAfterCommit: Bool,
        deliveryPollAttempts: Int,
        deliveryPollIntervalNanoseconds: UInt64,
        decodeResource: @Sendable (Data) throws -> Resource
    ) async -> UploadTransactionOutcome<Resource> {
        var current = latest

        switch current.recoveryDeliveryStatus {
        case .complete:
            return .success(current, reconciledAfterCommit: reconciledAfterCommit)
        case .failed(let state):
            return .commitFailed("Apple reported terminal upload state '\(state)'.", current)
        case .pending:
            break
        }

        for attempt in 0..<max(0, deliveryPollAttempts) {
            if Task.isCancelled {
                return pendingOrUnresolved(
                    commitConfirmed: commitConfirmed,
                    message: context ?? "Upload delivery verification was cancelled.",
                    resource: current,
                    reconciledAfterCommit: reconciledAfterCommit
                )
            }

            let data: Data
            do {
                data = try await httpClient.get(endpoint)
            } catch {
                let message = context.map { "\($0) Delivery verification also failed: \(error.localizedDescription)" }
                    ?? "Upload delivery could not be verified: \(error.localizedDescription)"
                return pendingOrUnresolved(
                    commitConfirmed: commitConfirmed,
                    message: message,
                    resource: current,
                    reconciledAfterCommit: true
                )
            }

            let fetched: Resource
            do {
                fetched = try decodeResource(data)
            } catch {
                let message = context.map { "\($0) Apple returned an unreadable delivery response: \(error.localizedDescription)" }
                    ?? "Apple returned an unreadable upload delivery response: \(error.localizedDescription)"
                return pendingOrUnresolved(
                    commitConfirmed: commitConfirmed,
                    message: message,
                    resource: current,
                    reconciledAfterCommit: true
                )
            }

            guard fetched.id == expectedID, fetched.type == expectedType else {
                return .commitUnresolved(
                    context ?? "Apple returned an unexpected resource during upload delivery verification.",
                    current
                )
            }
            current = fetched

            switch current.recoveryDeliveryStatus {
            case .complete:
                return .success(current, reconciledAfterCommit: true)
            case .failed(let state):
                return .commitFailed("Apple reported terminal upload state '\(state)'.", current)
            case .pending:
                break
            }

            if attempt + 1 < deliveryPollAttempts {
                do {
                    try await Task.sleep(nanoseconds: deliveryPollIntervalNanoseconds)
                } catch {
                    return pendingOrUnresolved(
                        commitConfirmed: commitConfirmed,
                        message: context ?? "Upload delivery verification was cancelled.",
                        resource: current,
                        reconciledAfterCommit: true
                    )
                }
            }
        }

        let state: String
        switch current.recoveryDeliveryStatus {
        case .pending(let value):
            state = value ?? "unknown"
        case .complete(let value), .failed(let value):
            state = value
        }
        let message = context.map { "\($0) Apple currently reports upload state '\(state)'." }
            ?? "The upload was committed, but Apple still reports state '\(state)'."
        return pendingOrUnresolved(
            commitConfirmed: commitConfirmed,
            message: message,
            resource: current,
            reconciledAfterCommit: reconciledAfterCommit || deliveryPollAttempts > 0
        )
    }

    private static func pendingOrUnresolved<Resource: RecoverableUploadResource>(
        commitConfirmed: Bool,
        message: String,
        resource: Resource,
        reconciledAfterCommit: Bool
    ) -> UploadTransactionOutcome<Resource> {
        if commitConfirmed {
            return .processingPending(
                message,
                resource,
                reconciledAfterCommit: reconciledAfterCommit
            )
        }
        return .commitUnresolved(message, resource)
    }

    private static func rollbackReservation(
        httpClient: HTTPClient,
        endpoint: String,
        policy: UploadReservationCleanupPolicy
    ) async -> UploadCleanupOutcome {
        if case .retain(let reason) = policy {
            return .unavailable(reason)
        }

        let task = Task.detached { () -> UploadCleanupOutcome in
            do {
                _ = try await httpClient.delete(endpoint)
                return .deleted
            } catch let error as ASCError {
                if case .deleteCommittedUnverified(let statusCode) = error {
                    return .committedUnverified(
                        statusCode: statusCode,
                        reason: Redactor.redact(error.localizedDescription)
                    )
                }
                if case .deleteOutcomeUnknown = error {
                    return .commitUnknown(Redactor.redact(error.localizedDescription))
                }
                if error.uploadRecoveryHTTPStatusCode == 404 {
                    return .alreadyAbsent
                }
                return .failed(Redactor.redact(error.localizedDescription))
            } catch {
                return .failed(Redactor.redact(error.localizedDescription))
            }
        }
        return await task.value
    }

    private static func payload<Resource: RecoverableUploadResource>(
        for outcome: UploadTransactionOutcome<Resource>,
        descriptor: UploadRecoveryDescriptor,
        format: (Resource) -> [String: Any]
    ) -> (value: [String: Any], text: String?, isError: Bool) {
        switch outcome {
        case .success(let resource, let reconciled):
            var value: [String: Any] = [
                "success": true,
                descriptor.successKey: format(resource)
            ]
            if reconciled {
                value["reconciledAfterCommit"] = true
            }
            return (value, nil, false)

        case .processingPending(let message, let resource, let reconciled):
            let safeMessage = Redactor.redact(message)
            var value: [String: Any] = [
                "success": true,
                "uploadCommitted": true,
                "processingComplete": false,
                "deliveryPending": true,
                "retrySafe": false,
                "reservationDeleted": false,
                "resourceId": resource.id,
                descriptor.idArgument: resource.id,
                descriptor.successKey: format(resource),
                "cleanup": retainedGuidance(
                    resourceID: resource.id,
                    reason: postCommitRetentionReason(
                        deletable: descriptor.deleteTool != nil,
                        deletableReason: "Automatic deletion was not attempted because Apple is still processing the committed upload.",
                        retainedReason: "The API exposes no cleanup operation for this resource. Inspect the processing state in App Store Connect or contact Apple Support."
                    ),
                    descriptor: descriptor
                )
            ]
            if reconciled {
                value["reconciledAfterCommit"] = true
            }
            return (
                value,
                "Upload committed successfully. \(safeMessage) Inspect the existing resource instead of starting another upload.",
                false
            )

        case .beforeReservation(let message):
            let safeMessage = Redactor.redact(message)
            return (
                [
                    "success": false,
                    "error": safeMessage,
                    "reservationCreated": false,
                    "retrySafe": true
                ],
                "Error: \(safeMessage)",
                true
            )

        case .reservationUnresolved(let message, let checksumReceipt):
            let safeMessage = Redactor.redact(message)
            var value: [String: Any] = [
                "success": false,
                "error": safeMessage,
                "reservationState": "unknown",
                "reservationIdKnown": false,
                "retrySafe": false,
                "inspection": inspectionGuidance(descriptor)
            ]
            let receiptPublished: Bool
            if let checksumReceiptKey = descriptor.checksumReceiptKey,
               let checksumReceipt {
                value[checksumReceiptKey] = checksumReceipt
                receiptPublished = true
            } else {
                receiptPublished = false
            }
            let recoveryInstruction = receiptPublished
                ? "Preserve the checksum receipt and inspect the parent collection before retrying to avoid a duplicate."
                : "Inspect the parent collection before retrying to avoid a duplicate."
            return (
                value,
                "Error: \(safeMessage) The reservation id is unavailable. \(recoveryInstruction)",
                true
            )

        case .reservationRejected(let message):
            let safeMessage = Redactor.redact(message)
            return (
                [
                    "success": false,
                    "error": safeMessage,
                    "reservationState": "rejected",
                    "reservationCreated": false,
                    "retrySafe": true
                ],
                "Error: \(safeMessage)",
                true
            )

        case .preCommitFailure(let message, let resource, let cleanup, let checksumReceipt):
            let safeMessage = Redactor.redact(message)
            let manualGuidance: String
            if cleanup.reservationDeleted {
                manualGuidance = ""
            } else if cleanup.outcomeUnknown || cleanup.completionUnverified {
                manualGuidance = " Inspect the exact reservation before another cleanup attempt."
            } else if let deleteTool = descriptor.deleteTool {
                manualGuidance = " Use \(deleteTool) with \(descriptor.idArgument) '\(resource.id)' to retry cleanup."
            } else {
                manualGuidance = " Inspect the retained reservation before retrying."
            }
            var value: [String: Any] = [
                    "success": false,
                    "error": safeMessage,
                    "resourceId": resource.id,
                    descriptor.idArgument: resource.id,
                    descriptor.successKey: format(resource),
                    "cleanup": cleanupGuidance(cleanup, resourceID: resource.id, descriptor: descriptor),
                    "reservationDeleted": cleanup.reservationDeleted,
                    "retrySafe": cleanup.reservationDeleted
                ]
            if let checksumReceiptKey = descriptor.checksumReceiptKey,
               let checksumReceipt {
                value[checksumReceiptKey] = checksumReceipt
            }
            if cleanup.outcomeUnknown {
                value["operationCommitState"] = "unknown"
                value["outcomeUnknown"] = true
            }
            if cleanup.completionUnverified {
                value["operationCommitState"] = "committed_unverified"
                value["operationCommitted"] = true
                value["inspectionRequired"] = true
            }
            return (
                value,
                "Error: \(safeMessage) Cleanup status: \(cleanup.status).\(manualGuidance)",
                true
            )

        case .commitFailed(let message, let resource):
            let safeMessage = Redactor.redact(message)
            let retentionReason = postCommitRetentionReason(
                deletable: descriptor.deleteTool != nil,
                deletableReason: "Automatic deletion was not attempted after commit; inspect the terminal failure before deleting.",
                retainedReason: "The API exposes no cleanup operation for this resource. Inspect the terminal failure in App Store Connect or contact Apple Support."
            )
            let retentionText = descriptor.deleteTool == nil
                ? "The failed resource was retained for inspection in App Store Connect or with Apple Support."
                : "The failed resource was retained for inspection and explicit deletion."
            return (
                [
                    "success": false,
                    "error": safeMessage,
                    "resourceId": resource.id,
                    descriptor.idArgument: resource.id,
                    descriptor.successKey: format(resource),
                    "deliveryPending": false,
                    "cleanup": retainedGuidance(
                        resourceID: resource.id,
                        reason: retentionReason,
                        descriptor: descriptor
                    ),
                    "reservationDeleted": false,
                    "retrySafe": false
                ],
                "Error: \(safeMessage) \(retentionText)",
                true
            )

        case .commitUnresolved(let message, let resource):
            let safeMessage = Redactor.redact(message)
            let retentionReason = postCommitRetentionReason(
                deletable: descriptor.deleteTool != nil,
                deletableReason: "Automatic deletion was not attempted because the commit or processing outcome is unresolved.",
                retainedReason: "The API exposes no cleanup operation for this resource. Inspect the unresolved outcome in App Store Connect or contact Apple Support."
            )
            let retentionText = descriptor.deleteTool == nil
                ? "The reservation was retained. Inspect it in App Store Connect or contact Apple Support before starting another upload."
                : "The reservation was retained. Inspect it before deleting or starting another upload."
            return (
                [
                    "success": false,
                    "error": safeMessage,
                    "resourceId": resource.id,
                    descriptor.idArgument: resource.id,
                    descriptor.successKey: format(resource),
                    "deliveryPending": true,
                    "cleanup": retainedGuidance(
                        resourceID: resource.id,
                        reason: retentionReason,
                        descriptor: descriptor
                    ),
                    "reservationDeleted": false,
                    "retrySafe": false
                ],
                "Error: \(safeMessage) \(retentionText)",
                true
            )
        }
    }

    private static func cleanupGuidance(
        _ cleanup: UploadCleanupOutcome,
        resourceID: String,
        descriptor: UploadRecoveryDescriptor
    ) -> [String: Any] {
        var value: [String: Any] = [
            "status": cleanup.status,
            "resourceId": resourceID
        ]
        if case .failed(let reason) = cleanup {
            value["reason"] = reason
            if let deleteTool = descriptor.deleteTool {
                value["tool"] = deleteTool
                value["arguments"] = [descriptor.idArgument: resourceID]
            }
        }
        if case .commitUnknown(let reason) = cleanup {
            value["reason"] = reason
            value["operationCommitState"] = "unknown"
            value["outcomeUnknown"] = true
            value["retrySafe"] = false
            value["inspectTool"] = descriptor.getTool ?? descriptor.inspectionTool
            value["inspectArguments"] = descriptor.getIDArgument.map { [$0: resourceID] }
                ?? descriptor.inspectionArguments
        }
        if case .committedUnverified(let statusCode, let reason) = cleanup {
            value["reason"] = reason
            value["statusCode"] = statusCode
            value["operationCommitState"] = "committed_unverified"
            value["operationCommitted"] = true
            value["retrySafe"] = false
            value["inspectionRequired"] = true
            value["inspectTool"] = descriptor.getTool ?? descriptor.inspectionTool
            value["inspectArguments"] = descriptor.getIDArgument.map { [$0: resourceID] }
                ?? descriptor.inspectionArguments
        }
        if case .unavailable(let reason) = cleanup {
            value["reason"] = reason
            value["inspectTool"] = descriptor.getTool ?? descriptor.inspectionTool
            value["inspectArguments"] = descriptor.getIDArgument.map { [$0: resourceID] }
                ?? descriptor.inspectionArguments
        }
        return value
    }

    private static func retainedGuidance(
        resourceID: String,
        reason: String,
        descriptor: UploadRecoveryDescriptor
    ) -> [String: Any] {
        var inspectArguments = descriptor.inspectionArguments
        if let idArgument = descriptor.getIDArgument {
            inspectArguments = [idArgument: resourceID]
        }

        var value: [String: Any] = [
            "status": "not_attempted",
            "reason": reason,
            "inspectTool": descriptor.getTool ?? descriptor.inspectionTool,
            "inspectArguments": inspectArguments
        ]
        if let deleteTool = descriptor.deleteTool {
            value["tool"] = deleteTool
            value["arguments"] = [descriptor.idArgument: resourceID]
        }
        if descriptor.getTool == nil {
            value["inspectTool"] = descriptor.inspectionTool
        }
        return value
    }

    private static func postCommitRetentionReason(
        deletable: Bool,
        deletableReason: String,
        retainedReason: String
    ) -> String {
        deletable ? deletableReason : retainedReason
    }

    private static func inspectionGuidance(_ descriptor: UploadRecoveryDescriptor) -> [String: Any] {
        [
            "tool": descriptor.inspectionTool,
            "arguments": descriptor.inspectionArguments
        ]
    }
}

extension ASCScreenshot: RecoverableUploadResource {
    var recoveryUploadOperations: [ASCUploadOperation]? { attributes?.uploadOperations }

    var recoveryDeliveryStatus: UploadDeliveryStatus {
        uploadMediaDeliveryStatus(attributes?.assetDeliveryState?.state)
    }
}

extension ASCPreview: RecoverableUploadResource {
    var recoveryUploadOperations: [ASCUploadOperation]? { attributes?.uploadOperations }

    var recoveryDeliveryStatus: UploadDeliveryStatus {
        uploadMediaDeliveryStatus(
            attributes?.videoDeliveryState?.state ?? attributes?.assetDeliveryState?.state
        )
    }
}

extension ASCIAPImage: RecoverableUploadResource {
    var recoveryUploadOperations: [ASCUploadOperation]? { attributes?.uploadOperations }

    var recoveryDeliveryStatus: UploadDeliveryStatus {
        uploadLegacyImageDeliveryStatus(attributes?.state)
    }
}

extension ASCIAPReviewScreenshot: RecoverableUploadResource {
    var recoveryUploadOperations: [ASCUploadOperation]? { attributes?.uploadOperations }

    var recoveryDeliveryStatus: UploadDeliveryStatus {
        uploadMediaDeliveryStatus(attributes?.assetDeliveryState?.state)
    }
}

extension ASCSubscriptionImage: RecoverableUploadResource {
    var recoveryUploadOperations: [ASCUploadOperation]? { attributes?.uploadOperations }

    var recoveryDeliveryStatus: UploadDeliveryStatus {
        uploadLegacyImageDeliveryStatus(attributes?.state)
    }
}

extension ASCSubReviewScreenshot: RecoverableUploadResource {
    var recoveryUploadOperations: [ASCUploadOperation]? { attributes?.uploadOperations }

    var recoveryDeliveryStatus: UploadDeliveryStatus {
        uploadMediaDeliveryStatus(attributes?.assetDeliveryState?.state)
    }
}

private func uploadMediaDeliveryStatus(_ state: String?) -> UploadDeliveryStatus {
    switch state {
    case "COMPLETE":
        return .complete("COMPLETE")
    case "FAILED":
        return .failed("FAILED")
    default:
        return .pending(state)
    }
}

private func uploadLegacyImageDeliveryStatus(_ state: String?) -> UploadDeliveryStatus {
    switch state {
    case "PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "APPROVED", "REJECTED":
        return .complete(state ?? "PREPARE_FOR_SUBMISSION")
    case "FAILED":
        return .failed("FAILED")
    default:
        return .pending(state)
    }
}

private extension ASCError {
    var uploadRecoveryHTTPStatusCode: Int? {
        switch self {
        case .api(_, let statusCode), .apiResponse(_, let statusCode):
            return statusCode
        case .deleteOutcomeUnknown(let cause):
            return cause.uploadRecoveryHTTPStatusCode
        case .deleteCommittedUnverified(let statusCode):
            return statusCode
        default:
            return nil
        }
    }
}
