import Foundation
import MCP

enum BuildUploadParentOwnership: Sendable {
    case created
    case existing

    var canAutoDeleteBeforeCommit: Bool {
        if case .created = self { return true }
        return false
    }
}

enum BuildUploadCleanupOutcome: Sendable {
    case deleted
    case alreadyAbsent
    case notAttempted
    case rejected(String)
    case outcomeUnknown(String)
    case committedUnverified(Int)

    var status: String {
        switch self {
        case .deleted: "deleted"
        case .alreadyAbsent: "already_absent"
        case .notAttempted: "not_attempted"
        case .rejected: "rejected"
        case .outcomeUnknown: "unknown"
        case .committedUnverified: "committed_unverified"
        }
    }

    var parentDeleted: Bool {
        switch self {
        case .deleted, .alreadyAbsent: true
        case .notAttempted, .rejected, .outcomeUnknown, .committedUnverified: false
        }
    }
}

extension BuildUploadsWorker {
    func uploadBuild(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters: app_id, file_path, short_version, build_version, platform, uti")
        }

        let fingerprint: BuildUploadFingerprint
        let filePath: String
        let assetType: String
        let uti: String
        let transferAttempts: Int
        do {
            fingerprint = try buildUploadFingerprint(arguments)
            guard let value = nonemptyString(arguments["file_path"]), value.hasPrefix("/") else {
                throw BuildUploadArgumentError("'file_path' must be an absolute path")
            }
            filePath = value
            _ = try canonicalFileName(
                URL(fileURLWithPath: filePath).lastPathComponent,
                field: "file_path basename"
            )
            if let rawAssetType = arguments["asset_type"] {
                guard let value = nonemptyString(rawAssetType) else {
                    throw BuildUploadArgumentError("'asset_type' must be a non-empty string when supplied")
                }
                assetType = value
            } else {
                assetType = "ASSET"
            }
            guard Self.assetTypeValues.contains(assetType) else {
                throw BuildUploadArgumentError("'asset_type' has an unsupported value")
            }
            guard let value = nonemptyString(arguments["uti"]), Self.utiValues.contains(value) else {
                throw BuildUploadArgumentError("'uti' is required and must use an Apple BuildUploadFile value")
            }
            uti = value
            transferAttempts = try boundedInteger(
                arguments["max_transfer_attempts"],
                field: "max_transfer_attempts",
                range: 1...5,
                defaultValue: maxTransferAttempts
            )
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        let snapshot: UploadFileSnapshot
        do {
            snapshot = try await uploadService.prepareSnapshot(filePath: filePath)
        } catch {
            return beforeParentResult(
                "Failed to create an immutable build upload snapshot: \(Redactor.redact(error.localizedDescription))"
            )
        }
        defer { snapshot.discard() }
        guard (1...Self.maximumFileSize).contains(snapshot.fileSize) else {
            return beforeParentResult("The immutable build upload snapshot size is outside Apple's supported range.")
        }

        let parentOutcome = await createBuildUploadParent(fingerprint)
        let parent: ASCBuildUpload
        switch parentOutcome {
        case .created(let value):
            parent = value
        case .recovered(let value, let commitState):
            return recoveredParentContinuationResult(
                parent: value,
                filePath: filePath,
                snapshot: snapshot,
                assetType: assetType,
                uti: uti,
                maxTransferAttempts: transferAttempts,
                commitState: commitState
            )
        case .unresolved(let message, let candidateIDs, let commitState):
            return parentUnresolvedResult(
                message,
                fingerprint: fingerprint,
                candidateIDs: candidateIDs,
                snapshot: snapshot,
                commitState: commitState
            )
        case .beforeRequest, .rejected:
            return buildUploadCreationResult(parentOutcome, fingerprint: fingerprint)
        }

        guard parent.attributes?.state?.state == "AWAITING_UPLOAD" else {
            return await preCommitFailureResult(
                "Apple returned a build upload parent that is not in AWAITING_UPLOAD state.",
                parent: parent,
                file: nil,
                ownership: .created,
                receipts: []
            )
        }

        if Task.isCancelled {
            return await preCommitFailureResult(
                "Build upload was cancelled after parent creation.",
                parent: parent,
                file: nil,
                ownership: .created,
                receipts: []
            )
        }

        let fileFingerprint = BuildUploadFileFingerprint(
            buildUploadID: parent.id,
            assetType: assetType,
            fileName: snapshot.fileName,
            fileSize: snapshot.fileSize,
            uti: uti
        )
        let reservation = await reserveBuildUploadFileResource(fileFingerprint)
        let file: ASCBuildUploadFile
        switch reservation {
        case .created(let value):
            file = value
        case .recovered(let value, let commitState):
            return recoveredReservationContinuationResult(
                parent: parent,
                file: value,
                filePath: filePath,
                snapshot: snapshot,
                assetType: assetType,
                uti: uti,
                maxTransferAttempts: transferAttempts,
                commitState: commitState
            )
        case .beforeRequest(let message):
            return await preCommitFailureResult(
                message,
                parent: parent,
                file: nil,
                ownership: .created,
                receipts: []
            )
        case .rejected(let message):
            return await preCommitFailureResult(
                message,
                parent: parent,
                file: nil,
                ownership: .created,
                receipts: [],
                operationCommitState: ASCNonIdempotentWriteFailureDisposition.rejected.rawValue
            )
        case .unresolved(let message, let candidateIDs, let commitState):
            return reservationUnresolvedResult(
                message,
                parent: parent,
                candidateIDs: candidateIDs,
                snapshot: snapshot,
                commitState: commitState
            )
        }

        return await transferCommitAndReconcile(
            parent: parent,
            file: file,
            snapshot: snapshot,
            ownership: .created,
            maxTransferAttempts: transferAttempts
        )
    }

    func uploadBuildFile(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let filePath = nonemptyString(arguments["file_path"]),
              filePath.hasPrefix("/") else {
            return MCPResult.error("Required parameters: build_upload_id and absolute file_path")
        }

        let buildUploadID: String
        let transferAttempts: Int
        let expectedMD5: String?
        let requestedFileID: String?
        let requestedAssetType: String?
        let requestedUTI: String?
        do {
            buildUploadID = try canonicalIdentifier(
                arguments["build_upload_id"],
                field: "build_upload_id"
            )
            expectedMD5 = try expectedSnapshotMD5(arguments["expected_md5"])
            if arguments["file_id"] != nil {
                requestedFileID = try canonicalIdentifier(arguments["file_id"], field: "file_id")
            } else {
                requestedFileID = nil
            }
            if let rawAssetType = arguments["asset_type"] {
                guard let value = nonemptyString(rawAssetType), Self.assetTypeValues.contains(value) else {
                    throw BuildUploadArgumentError("'asset_type' has an unsupported or invalid value")
                }
                requestedAssetType = value
            } else {
                requestedAssetType = nil
            }
            if let rawUTI = arguments["uti"] {
                guard let value = nonemptyString(rawUTI), Self.utiValues.contains(value) else {
                    throw BuildUploadArgumentError("'uti' has an unsupported or invalid value")
                }
                requestedUTI = value
            } else {
                requestedUTI = nil
            }
            if requestedFileID != nil, expectedMD5 == nil {
                throw BuildUploadArgumentError("'expected_md5' is required when 'file_id' is supplied")
            }
            if requestedFileID == nil,
               (requestedAssetType == nil || requestedUTI == nil) {
                throw BuildUploadArgumentError("asset_type and uti are required when file_id is omitted")
            }
            if requestedFileID == nil {
                _ = try canonicalFileName(
                    URL(fileURLWithPath: filePath).lastPathComponent,
                    field: "file_path basename"
                )
            }
            transferAttempts = try boundedInteger(
                arguments["max_transfer_attempts"],
                field: "max_transfer_attempts",
                range: 1...5,
                defaultValue: maxTransferAttempts
            )
        } catch {
            return MCPResult.error(error.localizedDescription)
        }

        let snapshot: UploadFileSnapshot
        do {
            snapshot = try await uploadService.prepareSnapshot(filePath: filePath)
        } catch {
            return beforeParentResult(
                "Failed to create an immutable build upload snapshot: \(Redactor.redact(error.localizedDescription))"
            )
        }
        defer { snapshot.discard() }
        guard (1...Self.maximumFileSize).contains(snapshot.fileSize) else {
            return beforeParentResult("The immutable build upload snapshot size is outside Apple's supported range.")
        }
        if let expectedMD5,
           snapshot.md5Checksum.caseInsensitiveCompare(expectedMD5) != .orderedSame {
            return snapshotMismatchResult(snapshot: snapshot, expectedMD5: expectedMD5)
        }

        let parent: ASCBuildUpload
        do {
            parent = try await fetchBuildUpload(buildUploadID)
        } catch {
            return retainedParentFailureResult(
                "Failed to confirm the existing build upload parent: \(Redactor.redact(error.localizedDescription))",
                parentID: buildUploadID,
                file: nil,
                receipts: []
            )
        }
        guard parent.attributes?.state?.state == "AWAITING_UPLOAD" else {
            return retainedParentFailureResult(
                "The existing build upload parent is not in AWAITING_UPLOAD state.",
                parentID: buildUploadID,
                file: nil,
                receipts: []
            )
        }

        let file: ASCBuildUploadFile
        if let fileID = requestedFileID {
            do {
                let members = try await allBuildUploadFiles(buildUploadID)
                guard members.contains(where: { $0.id == fileID }) else {
                    return retainedParentFailureResult(
                        "The supplied file_id is not related to the supplied build_upload_id.",
                        parentID: buildUploadID,
                        file: nil,
                        receipts: []
                    )
                }
                file = try await fetchBuildUploadFile(fileID)
                guard file.attributes?.fileName == snapshot.fileName,
                      file.attributes?.fileSize == snapshot.fileSize else {
                    return retainedParentFailureResult(
                        "The immutable snapshot name or size does not match the existing BuildUploadFile reservation.",
                        parentID: buildUploadID,
                        file: file,
                        receipts: []
                    )
                }
                if let expectedAssetType = requestedAssetType,
                   expectedAssetType != file.attributes?.assetType {
                    return retainedParentFailureResult(
                        "The supplied asset_type does not match the existing BuildUploadFile.",
                        parentID: buildUploadID,
                        file: file,
                        receipts: []
                    )
                }
                if let expectedUTI = requestedUTI,
                   expectedUTI != file.attributes?.uti {
                    return retainedParentFailureResult(
                        "The supplied uti does not match the existing BuildUploadFile.",
                        parentID: buildUploadID,
                        file: file,
                        receipts: []
                    )
                }
            } catch {
                return retainedParentFailureResult(
                    "Failed to verify the existing BuildUploadFile: \(Redactor.redact(error.localizedDescription))",
                    parentID: buildUploadID,
                    file: nil,
                    receipts: []
                )
            }
        } else {
            guard let assetType = requestedAssetType,
                  let uti = requestedUTI else {
                return MCPResult.error("asset_type and uti are required when file_id is omitted")
            }
            let fingerprint = BuildUploadFileFingerprint(
                buildUploadID: buildUploadID,
                assetType: assetType,
                fileName: snapshot.fileName,
                fileSize: snapshot.fileSize,
                uti: uti
            )
            let reservation = await reserveBuildUploadFileResource(fingerprint)
            switch reservation {
            case .created(let value):
                file = value
            case .recovered(let value, let commitState):
                return recoveredReservationContinuationResult(
                    parent: parent,
                    file: value,
                    filePath: filePath,
                    snapshot: snapshot,
                    assetType: assetType,
                    uti: uti,
                    maxTransferAttempts: transferAttempts,
                    commitState: commitState
                )
            case .beforeRequest(let message):
                return retainedParentFailureResult(
                    message,
                    parentID: buildUploadID,
                    file: nil,
                    receipts: []
                )
            case .rejected(let message):
                return retainedParentFailureResult(
                    message,
                    parentID: buildUploadID,
                    file: nil,
                    receipts: [],
                    operationCommitState: ASCNonIdempotentWriteFailureDisposition.rejected.rawValue,
                    retrySafe: true
                )
            case .unresolved(let message, let candidateIDs, let commitState):
                return reservationUnresolvedResult(
                    message,
                    parent: parent,
                    candidateIDs: candidateIDs,
                    snapshot: snapshot,
                    commitState: commitState
                )
            }
        }

        return await transferCommitAndReconcile(
            parent: parent,
            file: file,
            snapshot: snapshot,
            ownership: .existing,
            maxTransferAttempts: transferAttempts
        )
    }

    private func transferCommitAndReconcile(
        parent: ASCBuildUpload,
        file: ASCBuildUploadFile,
        snapshot: UploadFileSnapshot,
        ownership: BuildUploadParentOwnership,
        maxTransferAttempts: Int
    ) async -> CallTool.Result {
        let initialState = file.attributes?.assetDeliveryState?.state
        if initialState == "FAILED" {
            return terminalBuildUploadResult(
                "Apple reports FAILED for the BuildUploadFile.",
                parent: parent,
                file: file,
                receipts: []
            )
        }
        if initialState == "UPLOAD_COMPLETE" || initialState == "COMPLETE" {
            guard let fileChecksum = file.attributes?.sourceFileChecksums?.file,
                  let hash = fileChecksum.hash,
                  !hash.isEmpty else {
                return completedStateChecksumFailureResult(
                    "Apple reported \(initialState), but omitted sourceFileChecksums.file MD5 evidence.",
                    parent: parent,
                    file: file,
                    snapshot: snapshot,
                    appleAlgorithm: file.attributes?.sourceFileChecksums?.file?.algorithm,
                    appleHash: file.attributes?.sourceFileChecksums?.file?.hash
                )
            }
            guard fileChecksum.algorithm == "MD5" else {
                return completedStateChecksumFailureResult(
                    "Apple reported \(initialState), but sourceFileChecksums.file does not use MD5.",
                    parent: parent,
                    file: file,
                    snapshot: snapshot,
                    appleAlgorithm: fileChecksum.algorithm,
                    appleHash: hash
                )
            }
            guard hash.caseInsensitiveCompare(snapshot.md5Checksum) == .orderedSame else {
                return completedStateChecksumFailureResult(
                    "Apple reported \(initialState), but its file MD5 does not match the immutable snapshot.",
                    parent: parent,
                    file: file,
                    snapshot: snapshot,
                    appleAlgorithm: fileChecksum.algorithm,
                    appleHash: hash
                )
            }
            return await resolveCommittedBuildUpload(
                parent: parent,
                file: file,
                receipts: [],
                reconciledAfterCommit: true
            )
        }
        guard let initialState else {
            return await preCommitFailureResult(
                "Apple omitted assetDeliveryState.state for the BuildUploadFile.",
                parent: parent,
                file: file,
                ownership: ownership,
                receipts: []
            )
        }
        guard initialState == "AWAITING_UPLOAD" else {
            return retainedParentFailureResult(
                "Apple returned unsupported BuildUploadFile state '\(initialState)'.",
                parentID: parent.id,
                file: file,
                receipts: []
            )
        }
        guard let operations = file.attributes?.uploadOperations, !operations.isEmpty else {
            return await preCommitFailureResult(
                "Apple returned no upload operations for the BuildUploadFile.",
                parent: parent,
                file: file,
                ownership: ownership,
                receipts: []
            )
        }
        if Task.isCancelled {
            return await preCommitFailureResult(
                "Build upload was cancelled before presigned transfer.",
                parent: parent,
                file: file,
                ownership: ownership,
                receipts: []
            )
        }

        let transfer: UploadTransferResult
        do {
            transfer = try await uploadService.uploadFileWithReceipts(
                snapshot: snapshot,
                uploadOperations: operations,
                maxAttemptsPerPart: maxTransferAttempts,
                retryDelayNanoseconds: transferRetryDelayNanoseconds
            )
        } catch let failure as UploadTransferFailure {
            return await preCommitFailureResult(
                "Build upload byte transfer failed: \(Redactor.redact(failure.localizedDescription))",
                parent: parent,
                file: file,
                ownership: ownership,
                receipts: failure.receipts
            )
        } catch {
            return await preCommitFailureResult(
                "Build upload byte transfer failed: \(Redactor.redact(error.localizedDescription))",
                parent: parent,
                file: file,
                ownership: ownership,
                receipts: []
            )
        }

        if Task.isCancelled {
            return await preCommitFailureResult(
                "Build upload was cancelled before the file commit.",
                parent: parent,
                file: file,
                ownership: ownership,
                receipts: transfer.receipts
            )
        }

        let checksum: JSONValue = .object([
            "file": .object([
                "hash": .string(transfer.fileMD5),
                "algorithm": .string("MD5")
            ])
        ])
        let commit = await commitBuildUploadFileResource(
            fileID: file.id,
            attributes: ["sourceFileChecksums": checksum, "uploaded": .bool(true)]
        )
        switch commit {
        case .beforeRequest(let message):
            return await preCommitFailureResult(
                message,
                parent: parent,
                file: file,
                ownership: ownership,
                receipts: transfer.receipts,
                operationCommitState: "not_attempted"
            )
        case .committed(let committedFile, let reconciled):
            return await resolveCommittedBuildUpload(
                parent: parent,
                file: committedFile,
                receipts: transfer.receipts,
                reconciledAfterCommit: reconciled
            )
        case .terminalFailure(let message, let failedFile):
            return terminalBuildUploadResult(
                message,
                parent: parent,
                file: failedFile,
                receipts: transfer.receipts
            )
        case .rejected(let message):
            return commitRejectedResult(
                message,
                parent: parent,
                file: file,
                receipts: transfer.receipts
            )
        case .unresolved(let message, _, let lastKnown, let commitState):
            return commitUnresolvedResult(
                message,
                parent: parent,
                file: lastKnown ?? file,
                receipts: transfer.receipts,
                commitState: commitState
            )
        }
    }

    private func resolveCommittedBuildUpload(
        parent: ASCBuildUpload,
        file: ASCBuildUploadFile,
        receipts: [UploadPartReceipt],
        reconciledAfterCommit: Bool
    ) async -> CallTool.Result {
        var latestParent = parent
        var latestFile = file

        for attempt in 0..<pollAttempts {
            if latestFile.attributes?.assetDeliveryState?.state == "FAILED" {
                return terminalBuildUploadResult(
                    "Apple reports FAILED for the BuildUploadFile.",
                    parent: latestParent,
                    file: latestFile,
                    receipts: receipts
                )
            }
            if latestParent.attributes?.state?.state == "FAILED" {
                return terminalBuildUploadResult(
                    "Apple reports FAILED for the BuildUpload parent.",
                    parent: latestParent,
                    file: latestFile,
                    receipts: receipts
                )
            }
            if latestParent.attributes?.state?.state == "COMPLETE" {
                return completedBuildUploadResult(
                    parent: latestParent,
                    file: latestFile,
                    receipts: receipts,
                    reconciledAfterCommit: reconciledAfterCommit || attempt > 0
                )
            }
            if Task.isCancelled {
                return processingPendingResult(
                    "Build upload processing polling was cancelled after commit.",
                    parent: latestParent,
                    file: latestFile,
                    receipts: receipts,
                    reconciledAfterCommit: reconciledAfterCommit || attempt > 0
                )
            }

            do {
                async let fetchedFile = fetchBuildUploadFile(latestFile.id)
                async let fetchedParent = fetchBuildUpload(latestParent.id)
                latestFile = try await fetchedFile
                latestParent = try await fetchedParent
            } catch {
                return processingPendingResult(
                    "The upload was committed, but processing reconciliation failed: \(Redactor.redact(error.localizedDescription))",
                    parent: latestParent,
                    file: latestFile,
                    receipts: receipts,
                    reconciledAfterCommit: true
                )
            }

            if attempt + 1 < pollAttempts, pollIntervalNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                } catch {
                    return processingPendingResult(
                        "Build upload processing polling was cancelled after commit.",
                        parent: latestParent,
                        file: latestFile,
                        receipts: receipts,
                        reconciledAfterCommit: true
                    )
                }
            }
        }

        if latestFile.attributes?.assetDeliveryState?.state == "FAILED" ||
            latestParent.attributes?.state?.state == "FAILED" {
            return terminalBuildUploadResult(
                "Apple reports a terminal FAILED upload state.",
                parent: latestParent,
                file: latestFile,
                receipts: receipts
            )
        }
        if latestParent.attributes?.state?.state == "COMPLETE" {
            return completedBuildUploadResult(
                parent: latestParent,
                file: latestFile,
                receipts: receipts,
                reconciledAfterCommit: true
            )
        }
        return processingPendingResult(
            "The upload was committed, but Apple is still processing it.",
            parent: latestParent,
            file: latestFile,
            receipts: receipts,
            reconciledAfterCommit: true
        )
    }

    private func cleanupCreatedParent(_ parentID: String) async -> BuildUploadCleanupOutcome {
        let client = httpClient
        return await Task.detached { () -> BuildUploadCleanupOutcome in
            do {
                let receipt = try await client.deleteReceipt(
                    "/v1/buildUploads/\(try ASCPathSegment.encode(parentID))"
                )
                guard receipt.statusCode == 204 else {
                    return .committedUnverified(receipt.statusCode)
                }
                return .deleted
            } catch let error as ASCError where error.httpStatusCode == 404 {
                return .alreadyAbsent
            } catch {
                let disposition = ASCNonIdempotentWriteRecovery.failureDisposition(for: error, phase: .request)
                switch disposition {
                case .rejected:
                    return .rejected(Redactor.redact(error.localizedDescription))
                case .outcomeUnknown:
                    return .outcomeUnknown(Redactor.redact(error.localizedDescription))
                case .committedUnverified:
                    return .outcomeUnknown(Redactor.redact(error.localizedDescription))
                }
            }
        }.value
    }

    private func preCommitFailureResult(
        _ message: String,
        parent: ASCBuildUpload,
        file: ASCBuildUploadFile?,
        ownership: BuildUploadParentOwnership,
        receipts: [UploadPartReceipt],
        operationCommitState: String? = nil
    ) async -> CallTool.Result {
        let cleanup = ownership.canAutoDeleteBeforeCommit
            ? await cleanupCreatedParent(parent.id)
            : BuildUploadCleanupOutcome.notAttempted
        var payload: [String: Any] = [
            "success": false,
            "error": message,
            "buildUploadId": parent.id,
            "buildUpload": formatBuildUpload(parent),
            "commitAttempted": false,
            "automaticDeletionAttempted": ownership.canAutoDeleteBeforeCommit,
            "cleanup": cleanupPayload(cleanup, parentID: parent.id),
            "parentDeleted": cleanup.parentDeleted,
            "retrySafe": cleanup.parentDeleted,
            "transferReceipts": formatTransferReceipts(receipts)
        ]
        if let operationCommitState {
            payload["operationCommitState"] = operationCommitState
        }
        if let file {
            payload["fileId"] = file.id
            payload["buildUploadFile"] = formatBuildUploadFile(file, includeSensitive: false)
        }
        return MCPResult.jsonObject(
            payload,
            text: "Error: \(message) Parent cleanup status: \(cleanup.status).",
            isError: true
        )
    }

    private func beforeParentResult(_ message: String) -> CallTool.Result {
        MCPResult.jsonObject(
            [
                "success": false,
                "error": message,
                "parentCreated": false,
                "retrySafe": true
            ],
            text: "Error: \(message)",
            isError: true
        )
    }

    private func retainedParentFailureResult(
        _ message: String,
        parentID: String,
        file: ASCBuildUploadFile?,
        receipts: [UploadPartReceipt],
        operationCommitState: String? = nil,
        retrySafe: Bool = false
    ) -> CallTool.Result {
        var payload: [String: Any] = [
            "success": false,
            "error": message,
            "buildUploadId": parentID,
            "retrySafe": retrySafe,
            "automaticDeletionAttempted": false,
            "cleanup": cleanupPayload(.notAttempted, parentID: parentID),
            "transferReceipts": formatTransferReceipts(receipts)
        ]
        if let operationCommitState {
            payload["operationCommitState"] = operationCommitState
        }
        if let file {
            payload["fileId"] = file.id
            payload["buildUploadFile"] = formatBuildUploadFile(file, includeSensitive: false)
        }
        return MCPResult.jsonObject(
            payload,
            text: "Error: \(message) The existing parent was retained.",
            isError: true
        )
    }

    private func completedStateChecksumFailureResult(
        _ message: String,
        parent: ASCBuildUpload,
        file: ASCBuildUploadFile,
        snapshot: UploadFileSnapshot,
        appleAlgorithm: String?,
        appleHash: String?
    ) -> CallTool.Result {
        MCPResult.jsonObject(
            [
                "success": false,
                "error": message,
                "workflowState": "checksum_inspection_required",
                "operationCommitState": ASCNonIdempotentWriteFailureDisposition.committedUnverified.rawValue,
                "commitAttempted": false,
                "inspectionRequired": true,
                "buildUploadId": parent.id,
                "fileId": file.id,
                "buildUpload": formatBuildUpload(parent),
                "buildUploadFile": formatBuildUploadFile(file, includeSensitive: false),
                "checksumEvidence": [
                    "deliveryState": (file.attributes?.assetDeliveryState?.state).jsonSafe,
                    "snapshotChecksum": snapshot.md5Checksum,
                    "appleFileChecksum": [
                        "algorithm": appleAlgorithm.jsonSafe,
                        "checksum": appleHash.jsonSafe
                    ],
                    "verified": false
                ],
                "snapshotFingerprint": snapshotFingerprint(snapshot),
                "retrySafe": false,
                "automaticDeletionAttempted": false,
                "parentDeleted": false,
                "cleanup": cleanupPayload(.notAttempted, parentID: parent.id),
                "transferReceipts": [],
                "inspection": [
                    [
                        "tool": "build_uploads_get_file",
                        "arguments": ["file_id": file.id]
                    ],
                    [
                        "tool": "build_uploads_get",
                        "arguments": ["build_upload_id": parent.id]
                    ]
                ]
            ],
            text: "Error: \(message) The parent and file were retained; inspect both before any retry.",
            isError: true
        )
    }

    private func recoveredParentContinuationResult(
        parent: ASCBuildUpload,
        filePath: String,
        snapshot: UploadFileSnapshot,
        assetType: String,
        uti: String,
        maxTransferAttempts: Int,
        commitState: ASCNonIdempotentWriteFailureDisposition
    ) -> CallTool.Result {
        let continuationArguments: [String: Any] = [
            "build_upload_id": parent.id,
            "file_path": filePath,
            "expected_md5": snapshot.md5Checksum,
            "asset_type": assetType,
            "uti": uti,
            "max_transfer_attempts": maxTransferAttempts
        ]
        var payload: [String: Any] = [
            "success": false,
            "error": "A unique build upload candidate was observed after an ambiguous create, but this invocation cannot attribute it safely.",
            "workflowState": "continuation_required",
            "continuationRequired": true,
            "candidateAttributionConfirmed": false,
            "buildUploadId": parent.id,
            "buildUpload": formatBuildUpload(parent),
            "createdByInvocation": false,
            "automaticDeletionAttempted": false,
            "parentDeleted": false,
            "operationCommitState": commitState.rawValue,
            "write_outcome": commitState.rawValue,
            "retrySafe": false,
            "snapshotFingerprint": snapshotFingerprint(snapshot),
            "inspection": [
                "tool": "build_uploads_get",
                "arguments": ["build_upload_id": parent.id]
            ],
            "continuation": [
                "tool": "build_uploads_upload_file",
                "arguments": continuationArguments
            ]
        ]
        appendAmbiguousWriteState(commitState, to: &payload)
        return MCPResult.jsonObject(
            payload,
            text: "A candidate build upload '\(parent.id)' was observed but not attributed. Inspect it, then explicitly continue with build_uploads_upload_file.",
            isError: true
        )
    }

    private func recoveredReservationContinuationResult(
        parent: ASCBuildUpload,
        file: ASCBuildUploadFile,
        filePath: String,
        snapshot: UploadFileSnapshot,
        assetType: String,
        uti: String,
        maxTransferAttempts: Int,
        commitState: ASCNonIdempotentWriteFailureDisposition
    ) -> CallTool.Result {
        let continuationArguments: [String: Any] = [
            "build_upload_id": parent.id,
            "file_id": file.id,
            "file_path": filePath,
            "expected_md5": snapshot.md5Checksum,
            "asset_type": assetType,
            "uti": uti,
            "max_transfer_attempts": maxTransferAttempts
        ]
        var payload: [String: Any] = [
            "success": false,
            "error": "A unique BuildUploadFile candidate was observed after an ambiguous reservation, but this invocation cannot attribute it safely.",
            "workflowState": "continuation_required",
            "continuationRequired": true,
            "candidateAttributionConfirmed": false,
            "buildUploadId": parent.id,
            "fileId": file.id,
            "buildUpload": formatBuildUpload(parent),
            "buildUploadFile": formatBuildUploadFile(file, includeSensitive: false),
            "automaticDeletionAttempted": false,
            "parentDeleted": false,
            "operationCommitState": commitState.rawValue,
            "write_outcome": commitState.rawValue,
            "retrySafe": false,
            "snapshotFingerprint": snapshotFingerprint(snapshot),
            "inspection": [
                "tool": "build_uploads_get_file",
                "arguments": ["file_id": file.id]
            ],
            "continuation": [
                "tool": "build_uploads_upload_file",
                "arguments": continuationArguments
            ]
        ]
        appendAmbiguousWriteState(commitState, to: &payload)
        return MCPResult.jsonObject(
            payload,
            text: "A candidate file '\(file.id)' under build upload '\(parent.id)' was observed but not attributed. Inspect both IDs, then explicitly continue with build_uploads_upload_file.",
            isError: true
        )
    }

    private func parentUnresolvedResult(
        _ message: String,
        fingerprint: BuildUploadFingerprint,
        candidateIDs: [String],
        snapshot: UploadFileSnapshot,
        commitState: ASCNonIdempotentWriteFailureDisposition
    ) -> CallTool.Result {
        var payload: [String: Any] = [
            "success": false,
            "error": message,
            "workflowState": "parent_unresolved",
            "operationCommitState": commitState.rawValue,
            "inspectionRequired": true,
            "candidateAttributionConfirmed": false,
            "candidateIds": candidateIDs.sorted(),
            "automaticDeletionAttempted": false,
            "retrySafe": false,
            "snapshotFingerprint": snapshotFingerprint(snapshot),
            "inspection": [
                "tool": "build_uploads_list",
                "arguments": [
                    "app_id": fingerprint.appID,
                    "short_version_strings": [fingerprint.shortVersion],
                    "build_versions": [fingerprint.buildVersion],
                    "platforms": [fingerprint.platform],
                    "limit": 200
                ],
                "continue_with_next_url": true,
                "require_unique_match_before_continuation": true
            ]
        ]
        if commitState == .outcomeUnknown {
            payload["outcomeUnknown"] = true
        } else if commitState == .committedUnverified {
            payload["operationCommitted"] = true
            payload["outcomeUnknown"] = false
        }
        return MCPResult.jsonObject(
            payload,
            text: "Error: \(message) No parent candidate was attributed. Inspect every page and require one exact fingerprint match before explicit continuation.",
            isError: true
        )
    }

    private func reservationUnresolvedResult(
        _ message: String,
        parent: ASCBuildUpload,
        candidateIDs: [String],
        snapshot: UploadFileSnapshot,
        commitState: ASCNonIdempotentWriteFailureDisposition
    ) -> CallTool.Result {
        var payload: [String: Any] = [
            "success": false,
            "error": message,
            "workflowState": "reservation_unresolved",
            "operationCommitState": commitState.rawValue,
            "inspectionRequired": true,
            "candidateAttributionConfirmed": false,
            "candidateIds": candidateIDs.sorted(),
            "buildUploadId": parent.id,
            "buildUpload": formatBuildUpload(parent),
            "automaticDeletionAttempted": false,
            "parentDeleted": false,
            "retrySafe": false,
            "snapshotFingerprint": snapshotFingerprint(snapshot),
            "cleanup": cleanupPayload(.notAttempted, parentID: parent.id),
            "inspection": [
                "tool": "build_uploads_list_files",
                "arguments": ["build_upload_id": parent.id, "limit": 200],
                "continue_with_next_url": true,
                "require_unique_match_before_continuation": true
            ]
        ]
        if commitState == .outcomeUnknown {
            payload["outcomeUnknown"] = true
        } else if commitState == .committedUnverified {
            payload["operationCommitted"] = true
            payload["outcomeUnknown"] = false
        }
        return MCPResult.jsonObject(
            payload,
            text: "Error: \(message) No file candidate was attributed. Inspect every page and require one exact fingerprint match before explicit continuation.",
            isError: true
        )
    }

    private func commitRejectedResult(
        _ message: String,
        parent: ASCBuildUpload,
        file: ASCBuildUploadFile,
        receipts: [UploadPartReceipt]
    ) -> CallTool.Result {
        MCPResult.jsonObject(
            [
                "success": false,
                "error": message,
                "operationCommitState": ASCNonIdempotentWriteFailureDisposition.rejected.rawValue,
                "commitState": "rejected",
                "buildUploadId": parent.id,
                "fileId": file.id,
                "buildUpload": formatBuildUpload(parent),
                "buildUploadFile": formatBuildUploadFile(file, includeSensitive: false),
                "retrySafe": false,
                "automaticDeletionAttempted": false,
                "cleanup": cleanupPayload(.notAttempted, parentID: parent.id),
                "transferReceipts": formatTransferReceipts(receipts)
            ],
            text: "Error: \(message) The PATCH was rejected after byte transfer; the parent and file were retained.",
            isError: true
        )
    }

    private func commitUnresolvedResult(
        _ message: String,
        parent: ASCBuildUpload,
        file: ASCBuildUploadFile,
        receipts: [UploadPartReceipt],
        commitState: ASCNonIdempotentWriteFailureDisposition
    ) -> CallTool.Result {
        var payload: [String: Any] = [
            "success": false,
            "error": message,
            "operationCommitState": commitState.rawValue,
            "commitState": commitState.rawValue,
            "buildUploadId": parent.id,
            "fileId": file.id,
            "buildUpload": formatBuildUpload(parent),
            "buildUploadFile": formatBuildUploadFile(file, includeSensitive: false),
            "retrySafe": false,
            "inspectionRequired": true,
            "automaticDeletionAttempted": false,
            "cleanup": cleanupPayload(.notAttempted, parentID: parent.id),
            "transferReceipts": formatTransferReceipts(receipts),
            "inspection": [
                "tool": "build_uploads_get_file",
                "arguments": ["file_id": file.id]
            ]
        ]
        if commitState == .outcomeUnknown {
            payload["outcomeUnknown"] = true
        } else if commitState == .committedUnverified {
            payload["operationCommitted"] = true
            payload["outcomeUnknown"] = false
        }
        return MCPResult.jsonObject(
            payload,
            text: "Error: \(message) The upload was retained because PATCH started and its exact outcome is not safely replayable.",
            isError: true
        )
    }

    private func terminalBuildUploadResult(
        _ message: String,
        parent: ASCBuildUpload,
        file: ASCBuildUploadFile,
        receipts: [UploadPartReceipt]
    ) -> CallTool.Result {
        MCPResult.jsonObject(
            [
                "success": false,
                "error": message,
                "processingComplete": false,
                "terminalFailure": true,
                "buildUploadId": parent.id,
                "fileId": file.id,
                "buildUpload": formatBuildUpload(parent),
                "buildUploadFile": formatBuildUploadFile(file, includeSensitive: false),
                "retrySafe": false,
                "automaticDeletionAttempted": false,
                "cleanup": cleanupPayload(.notAttempted, parentID: parent.id),
                "transferReceipts": formatTransferReceipts(receipts)
            ],
            text: "Error: \(message) The failed upload was retained for diagnostics. Inspect the parent before any explicit cleanup decision.",
            isError: true
        )
    }

    private func completedBuildUploadResult(
        parent: ASCBuildUpload,
        file: ASCBuildUploadFile,
        receipts: [UploadPartReceipt],
        reconciledAfterCommit: Bool
    ) -> CallTool.Result {
        let buildID = parent.relationships?.build?.data?.id
        return MCPResult.jsonObject([
            "success": true,
            "uploadCommitted": true,
            "processingComplete": true,
            "buildUploadId": parent.id,
            "fileId": file.id,
            "buildId": buildID.jsonSafe,
            "buildRelationshipPending": buildID == nil,
            "buildUpload": formatBuildUpload(parent),
            "buildUploadFile": formatBuildUploadFile(file, includeSensitive: false),
            "reconciledAfterCommit": reconciledAfterCommit,
            "retrySafe": false,
            "transferReceipts": formatTransferReceipts(receipts)
        ])
    }

    private func processingPendingResult(
        _ message: String,
        parent: ASCBuildUpload,
        file: ASCBuildUploadFile,
        receipts: [UploadPartReceipt],
        reconciledAfterCommit: Bool
    ) -> CallTool.Result {
        MCPResult.jsonObject(
            [
                "success": true,
                "uploadCommitted": true,
                "processingComplete": false,
                "deliveryPending": true,
                "message": message,
                "buildUploadId": parent.id,
                "fileId": file.id,
                "buildUpload": formatBuildUpload(parent),
                "buildUploadFile": formatBuildUploadFile(file, includeSensitive: false),
                "reconciledAfterCommit": reconciledAfterCommit,
                "retrySafe": false,
                "automaticDeletionAttempted": false,
                "cleanup": cleanupPayload(.notAttempted, parentID: parent.id),
                "transferReceipts": formatTransferReceipts(receipts)
            ],
            text: "Upload committed successfully. \(message) Inspect the existing upload instead of starting another one.",
            isError: false
        )
    }

    private func cleanupPayload(_ outcome: BuildUploadCleanupOutcome, parentID: String) -> [String: Any] {
        var payload: [String: Any] = [
            "status": outcome.status,
            "resourceType": "buildUploads",
            "buildUploadId": parentID,
            "inspectTool": "build_uploads_get",
            "inspectArguments": ["build_upload_id": parentID]
        ]
        switch outcome {
        case .rejected(let reason), .outcomeUnknown(let reason):
            payload["reason"] = reason
        case .committedUnverified(let statusCode):
            payload["statusCode"] = statusCode
            payload["reason"] = "Apple returned an unexpected successful status for DELETE; do not replay automatically."
        case .deleted, .alreadyAbsent, .notAttempted:
            break
        }
        return payload
    }

    private func snapshotFingerprint(_ snapshot: UploadFileSnapshot) -> [String: Any] {
        [
            "fileName": snapshot.fileName,
            "fileSize": snapshot.fileSize,
            "md5Checksum": snapshot.md5Checksum
        ]
    }

    private func expectedSnapshotMD5(_ value: Value?) throws -> String? {
        guard let value else { return nil }
        guard let checksum = value.stringValue,
              checksum.utf8.count == 32,
              checksum.unicodeScalars.allSatisfy({ scalar in
                  switch scalar.value {
                  case 48...57, 65...70, 97...102: true
                  default: false
                  }
              }) else {
            throw BuildUploadArgumentError("'expected_md5' must be exactly 32 hexadecimal characters")
        }
        return checksum
    }

    private func snapshotMismatchResult(
        snapshot: UploadFileSnapshot,
        expectedMD5: String
    ) -> CallTool.Result {
        MCPResult.jsonObject(
            [
                "success": false,
                "error": "The immutable snapshot does not match expected_md5; no App Store Connect request was attempted.",
                "requestAttempted": false,
                "snapshotMatched": false,
                "expectedChecksum": expectedMD5.lowercased(),
                "actualChecksum": snapshot.md5Checksum,
                "snapshotFingerprint": snapshotFingerprint(snapshot),
                "retrySafe": true
            ],
            text: "Error: The local file changed since the continuation was issued. No App Store Connect request was attempted.",
            isError: true
        )
    }
}
