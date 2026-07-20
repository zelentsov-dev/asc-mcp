import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Build Uploads Compound Safety Tests")
struct BuildUploadsCompoundSafetyTests {
    @Test("compound upload stops on a recovered parent and returns an explicit continuation")
    func recoveredParentRequiresExplicitContinuation() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: [])),
            .init(statusCode: 200, body: compoundBuildUploadResponse(id: "upload-candidate")),
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: ["upload-candidate"]))
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let payload = try compoundResultObject(result)
        let continuation = try compoundValueObject(payload["continuation"])
        let continuationArguments = try compoundValueObject(continuation["arguments"])
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["workflowState"] == .string("continuation_required"))
        #expect(payload["candidateAttributionConfirmed"] == .bool(false))
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["operationCommitted"] == .bool(true))
        #expect(payload["buildUploadId"] == .string("upload-candidate"))
        #expect(payload["parentDeleted"] == .bool(false))
        #expect(continuation["tool"] == .string("build_uploads_upload_file"))
        #expect(continuationArguments["build_upload_id"] == .string("upload-candidate"))
        #expect(continuationArguments["file_path"] == .string(fileURL.path))
        #expect(continuationArguments["expected_md5"] == .string("b95f67f61ebb03619622d798f45fc2d3"))
        #expect(continuationArguments["file_id"] == nil)
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "GET"])
        #expect(!requests.contains { $0.httpMethod == "DELETE" })
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("compound upload stops on a recovered file and never deletes its owned parent")
    func recoveredReservationRequiresExactFileContinuation() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: [])),
            .init(statusCode: 201, body: compoundBuildUploadResponse(id: "upload-owned")),
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: ["upload-owned"])),
            .init(statusCode: 200, body: compoundBuildUploadFilesList(ids: [], parentID: "upload-owned")),
            .init(
                statusCode: 408,
                body: compoundAPIError(status: 408)
            ),
            .init(
                statusCode: 200,
                body: compoundBuildUploadFilesList(
                    ids: ["file-candidate"],
                    parentID: "upload-owned",
                    fileName: fileURL.lastPathComponent
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let payload = try compoundResultObject(result)
        let continuation = try compoundValueObject(payload["continuation"])
        let continuationArguments = try compoundValueObject(continuation["arguments"])
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["candidateAttributionConfirmed"] == .bool(false))
        #expect(payload["operationCommitState"] == .string("unknown"))
        #expect(payload["outcomeUnknown"] == .bool(true))
        #expect(payload["operationCommitted"] == nil)
        #expect(payload["buildUploadId"] == .string("upload-owned"))
        #expect(payload["fileId"] == .string("file-candidate"))
        #expect(payload["parentDeleted"] == .bool(false))
        #expect(continuation["tool"] == .string("build_uploads_upload_file"))
        #expect(continuationArguments["build_upload_id"] == .string("upload-owned"))
        #expect(continuationArguments["file_id"] == .string("file-candidate"))
        #expect(continuationArguments["file_path"] == .string(fileURL.path))
        #expect(continuationArguments["expected_md5"] == .string("b95f67f61ebb03619622d798f45fc2d3"))
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "GET", "GET", "POST", "GET"])
        #expect(!requests.contains { $0.httpMethod == "DELETE" || $0.httpMethod == "PATCH" })
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("zero or multiple parent candidates remain unattributed", arguments: [0, 2])
    func unresolvedParentCandidatesAreSafe(_ candidateCount: Int) async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let candidateIDs = (0..<candidateCount).map { "upload-\($0)" }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: [])),
            .init(statusCode: 200, body: compoundBuildUploadResponse(id: "upload-response-only")),
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: candidateIDs))
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let payload = try compoundResultObject(result)
        let candidates = try compoundValueArray(payload["candidateIds"])
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["workflowState"] == .string("parent_unresolved"))
        #expect(payload["candidateAttributionConfirmed"] == .bool(false))
        #expect(payload["continuation"] == nil)
        #expect(candidates == candidateIDs.map(Value.string))
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "GET"])
        #expect(!requests.contains { $0.httpMethod == "DELETE" || $0.httpMethod == "PATCH" })
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("zero or multiple reservation candidates remain unattributed", arguments: [0, 2])
    func unresolvedReservationCandidatesAreSafe(_ candidateCount: Int) async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let candidateIDs = (0..<candidateCount).map { "file-\($0)" }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: [])),
            .init(statusCode: 201, body: compoundBuildUploadResponse(id: "upload-owned")),
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: ["upload-owned"])),
            .init(statusCode: 200, body: compoundBuildUploadFilesList(ids: [], parentID: "upload-owned")),
            .init(
                statusCode: 200,
                body: compoundBuildUploadFileResponse(
                    id: "file-response-only",
                    fileName: fileURL.lastPathComponent
                )
            ),
            .init(
                statusCode: 200,
                body: compoundBuildUploadFilesList(
                    ids: candidateIDs,
                    parentID: "upload-owned",
                    fileName: fileURL.lastPathComponent
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let payload = try compoundResultObject(result)
        let candidates = try compoundValueArray(payload["candidateIds"])
        let cleanup = try compoundValueObject(payload["cleanup"])
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["workflowState"] == .string("reservation_unresolved"))
        #expect(payload["candidateAttributionConfirmed"] == .bool(false))
        #expect(payload["continuation"] == nil)
        #expect(candidates == candidateIDs.map(Value.string))
        #expect(payload["parentDeleted"] == .bool(false))
        #expect(cleanup["tool"] == nil)
        #expect(cleanup["arguments"] == nil)
        #expect(cleanup["inspectTool"] == .string("build_uploads_get"))
        #expect(!requests.contains { $0.httpMethod == "DELETE" || $0.httpMethod == "PATCH" })
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("a pre-existing 201 parent identity is never owned or deleted")
    func staleSuccessfulParentResponseIsNeverOwned() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: ["upload-stale"])),
            .init(statusCode: 201, body: compoundBuildUploadResponse(id: "upload-stale")),
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: ["upload-stale"]))
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let payload = try compoundResultObject(result)
        let candidates = try compoundValueArray(payload["candidateIds"])
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["workflowState"] == .string("parent_unresolved"))
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["candidateAttributionConfirmed"] == .bool(false))
        #expect(payload["automaticDeletionAttempted"] == .bool(false))
        #expect(candidates.isEmpty)
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "GET"])
        #expect(!requests.contains { $0.httpMethod == "DELETE" || $0.httpMethod == "PATCH" })
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("a fresh 201 parent outside the requested app is never owned")
    func misboundSuccessfulParentResponseIsNeverOwned() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: [])),
            .init(statusCode: 201, body: compoundBuildUploadResponse(id: "upload-wrong-app")),
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: []))
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let payload = try compoundResultObject(result)
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["workflowState"] == .string("parent_unresolved"))
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["automaticDeletionAttempted"] == .bool(false))
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "GET"])
        #expect(!requests.contains { $0.httpMethod == "DELETE" || $0.httpMethod == "PATCH" })
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("a fresh 201 file outside the requested parent is never transferred")
    func misboundSuccessfulReservationIsNeverTransferred() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: [])),
            .init(statusCode: 201, body: compoundBuildUploadResponse(id: "upload-owned")),
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: ["upload-owned"])),
            .init(statusCode: 200, body: compoundBuildUploadFilesList(ids: [], parentID: "upload-owned")),
            .init(
                statusCode: 201,
                body: compoundBuildUploadFileResponse(
                    id: "file-wrong-parent",
                    fileName: fileURL.lastPathComponent,
                    includeUploadOperation: true,
                    uploadPath: "/wrong-parent"
                )
            ),
            .init(statusCode: 200, body: compoundBuildUploadFilesList(ids: [], parentID: "upload-owned"))
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let payload = try compoundResultObject(result)
        let cleanup = try compoundValueObject(payload["cleanup"])
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["workflowState"] == .string("reservation_unresolved"))
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["automaticDeletionAttempted"] == .bool(false))
        #expect(payload["parentDeleted"] == .bool(false))
        #expect(cleanup["status"] == .string("not_attempted"))
        #expect(requests.map(\.httpMethod) == [
            "GET", "POST", "GET", "GET", "POST", "GET"
        ])
        #expect(!requests.contains { $0.httpMethod == "DELETE" || $0.httpMethod == "PATCH" })
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("explicit continuation rejects a same-size file mutation before any Apple request")
    func continuationChecksumPreconditionPreventsTOCTOU() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let expectedMD5 = "b95f67f61ebb03619622d798f45fc2d3"
        try Data([3, 4, 5]).write(to: fileURL, options: .atomic)
        let apiTransport = TestHTTPTransport(responses: [])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(.init(
            name: "build_uploads_upload_file",
            arguments: [
                "build_upload_id": .string("upload-candidate"),
                "file_id": .string("file-candidate"),
                "file_path": .string(fileURL.path),
                "expected_md5": .string(expectedMD5),
                "max_transfer_attempts": .int(1)
            ]
        ))
        let payload = try compoundResultObject(result)

        #expect(result.isError == true)
        #expect(payload["requestAttempted"] == .bool(false))
        #expect(payload["snapshotMatched"] == .bool(false))
        #expect(payload["expectedChecksum"] == .string(expectedMD5))
        #expect(payload["actualChecksum"] != .string(expectedMD5))
        #expect(payload["retrySafe"] == .bool(true))
        #expect(await apiTransport.requestCount() == 0)
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("present invalid optional upload arguments fail before network activity")
    func invalidOptionalUploadArgumentsFailBeforeNetwork() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let invalidCalls: [CallTool.Parameters] = [
            .init(
                name: "build_uploads_upload",
                arguments: [
                    "app_id": .string("app-1"),
                    "file_path": .string(fileURL.path),
                    "short_version": .string("2.4.0"),
                    "build_version": .string("240"),
                    "platform": .string("IOS"),
                    "asset_type": .null,
                    "uti": .string("com.apple.ipa")
                ]
            ),
            .init(
                name: "build_uploads_upload",
                arguments: [
                    "app_id": .string("app-1"),
                    "file_path": .string(fileURL.path),
                    "short_version": .string("2.4.0"),
                    "build_version": .string("240"),
                    "platform": .string("IOS"),
                    "asset_type": .int(1),
                    "uti": .string("com.apple.ipa")
                ]
            ),
            .init(
                name: "build_uploads_upload_file",
                arguments: [
                    "build_upload_id": .string("upload-existing"),
                    "file_id": .string("file-existing"),
                    "file_path": .string(fileURL.path),
                    "expected_md5": .string("b95f67f61ebb03619622d798f45fc2d3"),
                    "asset_type": .null
                ]
            ),
            .init(
                name: "build_uploads_upload_file",
                arguments: [
                    "build_upload_id": .string("upload-existing"),
                    "file_id": .string("file-existing"),
                    "file_path": .string(fileURL.path),
                    "expected_md5": .string("b95f67f61ebb03619622d798f45fc2d3"),
                    "uti": .int(1)
                ]
            ),
            .init(
                name: "build_uploads_upload_file",
                arguments: [
                    "build_upload_id": .string("upload-existing"),
                    "file_id": .null,
                    "file_path": .string(fileURL.path),
                    "expected_md5": .string("b95f67f61ebb03619622d798f45fc2d3"),
                    "asset_type": .string("ASSET"),
                    "uti": .string("com.apple.ipa")
                ]
            )
        ]

        for call in invalidCalls {
            let apiTransport = TestHTTPTransport(responses: [])
            let uploadTransport = TestHTTPTransport(responses: [])
            let worker = try await compoundWorker(
                apiTransport: apiTransport,
                uploadTransport: uploadTransport
            )

            let result = try await worker.handleTool(call)

            #expect(result.isError == true)
            #expect(await apiTransport.requestCount() == 0)
            #expect(await uploadTransport.requestCount() == 0)
        }
    }

    @Test("fresh reservations reject a noncanonical local file name before network activity")
    func noncanonicalSnapshotFileNameFailsBeforeNetwork() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-invalid-\(UUID().uuidString)\\name.ipa")
        try Data([0, 1, 2]).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let calls: [CallTool.Parameters] = [
            .init(
                name: "build_uploads_upload",
                arguments: [
                    "app_id": .string("app-1"),
                    "file_path": .string(fileURL.path),
                    "short_version": .string("2.4.0"),
                    "build_version": .string("240"),
                    "platform": .string("IOS"),
                    "asset_type": .string("ASSET"),
                    "uti": .string("com.apple.ipa")
                ]
            ),
            .init(
                name: "build_uploads_upload_file",
                arguments: [
                    "build_upload_id": .string("upload-existing"),
                    "file_path": .string(fileURL.path),
                    "asset_type": .string("ASSET"),
                    "uti": .string("com.apple.ipa")
                ]
            )
        ]

        for call in calls {
            let apiTransport = TestHTTPTransport(responses: [])
            let uploadTransport = TestHTTPTransport(responses: [])
            let worker = try await compoundWorker(
                apiTransport: apiTransport,
                uploadTransport: uploadTransport
            )

            let result = try await worker.handleTool(call)

            #expect(result.isError == true)
            #expect(await apiTransport.requestCount() == 0)
            #expect(await uploadTransport.requestCount() == 0)
        }
    }

    @Test("compound upload completes parent reservation PUT PATCH and processing reconciliation")
    func compoundUploadHappyPath() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = CompoundSuccessfulAPITransport(
            scenario: .compound,
            fileName: fileURL.lastPathComponent
        )
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, headers: ["ETag": "response-etag"], body: "")
        ])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let payload = try compoundResultObject(result)
        let receipts = try compoundValueArray(payload["transferReceipts"])
        let receipt = try compoundValueObject(try #require(receipts.first))
        let apiRequests = await apiTransport.recordedRequests()
        let uploadRequests = await uploadTransport.recordedRequests()

        #expect(result.isError != true)
        #expect(payload["processingComplete"] == .bool(true))
        #expect(payload["buildUploadId"] == .string("upload-owned"))
        #expect(payload["fileId"] == .string("file-owned"))
        #expect(payload["buildId"] == .string("build-1"))
        #expect(receipt["method"] == .string("PUT"))
        #expect(receipt["attempts"] == .int(1))
        #expect(receipt["entityTag"] == .string("apple-etag"))
        #expect(receipt["responseEntityTag"] == .string("response-etag"))
        #expect(!compoundValueContains(.object(payload), "asset-token-secret"))
        #expect(!compoundValueContains(.object(payload), "upload.example.test"))
        #expect(apiRequests.count == 9)
        #expect(apiRequests.filter { $0.httpMethod == "POST" }.count == 2)
        #expect(apiRequests.filter { $0.httpMethod == "PATCH" }.count == 1)
        #expect(apiRequests.filter { $0.httpMethod == "GET" }.count == 6)
        #expect(!apiRequests.contains { $0.httpMethod == "DELETE" })
        #expect(uploadRequests.count == 1)
        #expect(uploadRequests[0].httpMethod == "PUT")
        #expect(uploadRequests[0].url?.path == "/build")
        #expect(uploadRequests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(uploadRequests[0].httpBody == Data([0, 1, 2]))

        let patchRequest = try #require(apiRequests.first { $0.httpMethod == "PATCH" })
        let patchBody = try compoundJSONObject(try #require(patchRequest.httpBody))
        let patchData = try compoundJSONObject(patchBody["data"])
        let attributes = try compoundJSONObject(patchData["attributes"])
        let checksums = try compoundJSONObject(attributes["sourceFileChecksums"])
        let fileChecksum = try compoundJSONObject(checksums["file"])
        #expect(attributes["uploaded"] as? Bool == true)
        #expect(fileChecksum["algorithm"] as? String == "MD5")
        #expect(fileChecksum["hash"] as? String == "b95f67f61ebb03619622d798f45fc2d3")
    }

    @Test("resume succeeds only after membership and expected checksum validation")
    func resumeHappyPath() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = CompoundSuccessfulAPITransport(
            scenario: .resume,
            fileName: fileURL.lastPathComponent
        )
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(.init(
            name: "build_uploads_upload_file",
            arguments: [
                "build_upload_id": .string("upload-owned"),
                "file_id": .string("file-owned"),
                "file_path": .string(fileURL.path),
                "expected_md5": .string("B95F67F61EBB03619622D798F45FC2D3"),
                "max_transfer_attempts": .int(1)
            ]
        ))
        let payload = try compoundResultObject(result)
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError != true)
        #expect(payload["processingComplete"] == .bool(true))
        #expect(payload["buildUploadId"] == .string("upload-owned"))
        #expect(payload["fileId"] == .string("file-owned"))
        #expect(requests.count == 6)
        #expect(requests.filter { $0.httpMethod == "GET" }.count == 5)
        #expect(requests.filter { $0.httpMethod == "PATCH" }.count == 1)
        #expect(!requests.contains { $0.httpMethod == "POST" || $0.httpMethod == "DELETE" })
        #expect(await uploadTransport.requestCount() == 1)
    }

    @Test("an already-complete file succeeds only when Apple's MD5 matches the snapshot")
    func alreadyCompleteMatchingChecksumIsAccepted() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = CompoundSuccessfulAPITransport(
            scenario: .alreadyComplete(checksum: "B95F67F61EBB03619622D798F45FC2D3"),
            fileName: fileURL.lastPathComponent
        )
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(.init(
            name: "build_uploads_upload_file",
            arguments: [
                "build_upload_id": .string("upload-owned"),
                "file_id": .string("file-owned"),
                "file_path": .string(fileURL.path),
                "expected_md5": .string("b95f67f61ebb03619622d798f45fc2d3")
            ]
        ))
        let payload = try compoundResultObject(result)
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError != true)
        #expect(payload["processingComplete"] == .bool(true))
        #expect(payload["buildUploadId"] == .string("upload-owned"))
        #expect(payload["fileId"] == .string("file-owned"))
        #expect(requests.count == 5)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(!requests.contains { $0.httpMethod == "PATCH" })
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("an already-complete file with a different MD5 fails closed")
    func alreadyCompleteMismatchedChecksumIsRejected() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: [])),
            .init(statusCode: 201, body: compoundBuildUploadResponse(id: "upload-owned")),
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: ["upload-owned"])),
            .init(statusCode: 200, body: compoundBuildUploadFilesList(ids: [], parentID: "upload-owned")),
            .init(
                statusCode: 201,
                body: compoundBuildUploadFileResponse(
                    id: "file-owned",
                    fileName: fileURL.lastPathComponent,
                    state: "UPLOAD_COMPLETE",
                    fileChecksum: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                )
            ),
            .init(
                statusCode: 200,
                body: compoundBuildUploadFilesList(
                    ids: ["file-owned"],
                    parentID: "upload-owned",
                    fileName: fileURL.lastPathComponent,
                    state: "UPLOAD_COMPLETE",
                    fileChecksum: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let payload = try compoundResultObject(result)
        let evidence = try compoundValueObject(payload["checksumEvidence"])
        let appleChecksum = try compoundValueObject(evidence["appleFileChecksum"])
        let inspection = try compoundValueArray(payload["inspection"])
        let inspectionTools = try inspection.map {
            let item = try compoundValueObject($0)
            return try #require(item["tool"])
        }
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["success"] == .bool(false))
        #expect(payload["commitAttempted"] == .bool(false))
        #expect(payload["workflowState"] == .string("checksum_inspection_required"))
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["automaticDeletionAttempted"] == .bool(false))
        #expect(payload["parentDeleted"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(evidence["snapshotChecksum"] == .string("b95f67f61ebb03619622d798f45fc2d3"))
        #expect(appleChecksum["algorithm"] == .string("MD5"))
        #expect(appleChecksum["checksum"] == .string("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
        #expect(inspectionTools == [
            .string("build_uploads_get_file"),
            .string("build_uploads_get")
        ])
        #expect(requests.map(\.httpMethod) == [
            "GET", "POST", "GET", "GET", "POST", "GET"
        ])
        #expect(!requests.contains { $0.httpMethod == "PATCH" || $0.httpMethod == "DELETE" })
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("an already-complete file without Apple's MD5 fails closed")
    func alreadyCompleteMissingChecksumIsRejected() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = CompoundSuccessfulAPITransport(
            scenario: .alreadyComplete(checksum: nil),
            fileName: fileURL.lastPathComponent
        )
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(.init(
            name: "build_uploads_upload_file",
            arguments: [
                "build_upload_id": .string("upload-owned"),
                "file_id": .string("file-owned"),
                "file_path": .string(fileURL.path),
                "expected_md5": .string("b95f67f61ebb03619622d798f45fc2d3")
            ]
        ))
        let payload = try compoundResultObject(result)
        let evidence = try compoundValueObject(payload["checksumEvidence"])
        let appleChecksum = try compoundValueObject(evidence["appleFileChecksum"])
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["success"] == .bool(false))
        #expect(payload["commitAttempted"] == .bool(false))
        #expect(payload["workflowState"] == .string("checksum_inspection_required"))
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["automaticDeletionAttempted"] == .bool(false))
        #expect(payload["parentDeleted"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(evidence["snapshotChecksum"] == .string("b95f67f61ebb03619622d798f45fc2d3"))
        #expect(appleChecksum["algorithm"] == .null)
        #expect(appleChecksum["checksum"] == .null)
        #expect(requests.count == 3)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(!requests.contains { $0.httpMethod == "PATCH" || $0.httpMethod == "DELETE" })
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("an already-complete file with a non-MD5 checksum fails closed")
    func alreadyCompleteUnsupportedChecksumAlgorithmIsRejected() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadResponse(id: "upload-existing")),
            .init(
                statusCode: 200,
                body: compoundBuildUploadFilesList(
                    ids: ["file-existing"],
                    parentID: "upload-existing",
                    fileName: fileURL.lastPathComponent
                )
            ),
            .init(
                statusCode: 200,
                body: compoundBuildUploadFileResponse(
                    id: "file-existing",
                    fileName: fileURL.lastPathComponent,
                    state: "COMPLETE",
                    fileChecksum: "b95f67f61ebb03619622d798f45fc2d3",
                    fileChecksumAlgorithm: "SHA_256"
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(.init(
            name: "build_uploads_upload_file",
            arguments: [
                "build_upload_id": .string("upload-existing"),
                "file_id": .string("file-existing"),
                "file_path": .string(fileURL.path),
                "expected_md5": .string("b95f67f61ebb03619622d798f45fc2d3")
            ]
        ))
        let payload = try compoundResultObject(result)
        let evidence = try compoundValueObject(payload["checksumEvidence"])
        let appleChecksum = try compoundValueObject(evidence["appleFileChecksum"])
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["success"] == .bool(false))
        #expect(payload["operationCommitState"] == .string("committed_unverified"))
        #expect(payload["automaticDeletionAttempted"] == .bool(false))
        #expect(payload["parentDeleted"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(appleChecksum["algorithm"] == .string("SHA_256"))
        #expect(requests.count == 3)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(!requests.contains { $0.httpMethod == "PATCH" || $0.httpMethod == "DELETE" })
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("an existing parent is never deleted after a pre-commit file failure")
    func existingParentPreCommitFailureIsRetained() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadResponse(id: "upload-existing")),
            .init(
                statusCode: 200,
                body: compoundBuildUploadFilesList(
                    ids: ["file-existing"],
                    parentID: "upload-existing",
                    fileName: fileURL.lastPathComponent
                )
            ),
            .init(
                statusCode: 200,
                body: compoundBuildUploadFileResponse(
                    id: "file-existing",
                    fileName: fileURL.lastPathComponent
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(.init(
            name: "build_uploads_upload_file",
            arguments: [
                "build_upload_id": .string("upload-existing"),
                "file_id": .string("file-existing"),
                "file_path": .string(fileURL.path),
                "expected_md5": .string("b95f67f61ebb03619622d798f45fc2d3"),
                "max_transfer_attempts": .int(1)
            ]
        ))
        let payload = try compoundResultObject(result)
        let cleanup = try compoundValueObject(payload["cleanup"])
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["commitAttempted"] == .bool(false))
        #expect(payload["automaticDeletionAttempted"] == .bool(false))
        #expect(payload["parentDeleted"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(cleanup["status"] == .string("not_attempted"))
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "GET"])
        #expect(!requests.contains { $0.httpMethod == "POST" || $0.httpMethod == "PATCH" || $0.httpMethod == "DELETE" })
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("an incompatible existing parent state fails closed before file inspection")
    func incompatibleExistingParentStateStopsWorkflow() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: compoundBuildUploadResponse(
                    id: "upload-existing",
                    state: "COMPLETE",
                    buildID: "build-1"
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(.init(
            name: "build_uploads_upload_file",
            arguments: [
                "build_upload_id": .string("upload-existing"),
                "file_id": .string("file-existing"),
                "file_path": .string(fileURL.path),
                "expected_md5": .string("b95f67f61ebb03619622d798f45fc2d3")
            ]
        ))
        let payload = try compoundResultObject(result)
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["automaticDeletionAttempted"] == .bool(false))
        #expect(payload["buildUploadId"] == .string("upload-existing"))
        #expect(requests.map(\.httpMethod) == ["GET"])
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("a pre-commit failure cleans up only the exact parent created by this invocation")
    func exactOwnedParentCanBeCleanedBeforeCommit() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: [])),
            .init(statusCode: 201, body: compoundBuildUploadResponse(id: "upload-owned")),
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: ["upload-owned"])),
            .init(statusCode: 500, body: compoundAPIError(status: 500)),
            .init(statusCode: 204, body: "")
        ])
        let worker = try await compoundWorker(apiTransport: apiTransport)

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let payload = try compoundResultObject(result)
        let cleanup = try compoundValueObject(payload["cleanup"])
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["automaticDeletionAttempted"] == .bool(true))
        #expect(payload["parentDeleted"] == .bool(true))
        #expect(payload["retrySafe"] == .bool(true))
        #expect(cleanup["status"] == .string("deleted"))
        #expect(cleanup["tool"] == nil)
        #expect(cleanup["arguments"] == nil)
        #expect(cleanup["inspectTool"] == .string("build_uploads_get"))
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "GET", "GET", "DELETE"])
        #expect(requests.last?.url?.path == "/v1/buildUploads/upload-owned")
        #expect(!requests.contains { $0.url?.path.contains("/v1/buildUploadFiles/") == true && $0.httpMethod == "DELETE" })
    }

    @Test("an unexpected successful cleanup status is retained as committed-unverified")
    func cleanupRequiresExact204() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: [])),
            .init(statusCode: 201, body: compoundBuildUploadResponse(id: "upload-owned")),
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: ["upload-owned"])),
            .init(statusCode: 500, body: compoundAPIError(status: 500)),
            .init(statusCode: 200, body: "{}")
        ])
        let worker = try await compoundWorker(apiTransport: apiTransport)

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let payload = try compoundResultObject(result)
        let cleanup = try compoundValueObject(payload["cleanup"])
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["parentDeleted"] == .bool(false))
        #expect(payload["retrySafe"] == .bool(false))
        #expect(cleanup["status"] == .string("committed_unverified"))
        #expect(cleanup["statusCode"] == .int(200))
        #expect(cleanup["tool"] == nil)
        #expect(cleanup["arguments"] == nil)
        #expect(cleanup["inspectTool"] == .string("build_uploads_get"))
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "GET", "GET", "DELETE"])
    }

    @Test("missing file delivery state fails closed before byte transfer")
    func missingDeliveryStateNeverStartsTransfer() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: [])),
            .init(statusCode: 201, body: compoundBuildUploadResponse(id: "upload-owned")),
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: ["upload-owned"])),
            .init(statusCode: 200, body: compoundBuildUploadFilesList(ids: [], parentID: "upload-owned")),
            .init(
                statusCode: 201,
                body: compoundBuildUploadFileResponse(
                    id: "file-owned",
                    fileName: fileURL.lastPathComponent,
                    includeUploadOperation: true,
                    includeDeliveryState: false
                )
            ),
            .init(
                statusCode: 200,
                body: compoundBuildUploadFilesList(
                    ids: ["file-owned"],
                    parentID: "upload-owned",
                    fileName: fileURL.lastPathComponent,
                    includeUploadOperation: true,
                    includeDeliveryState: false
                )
            ),
            .init(statusCode: 204, body: "")
        ])
        let uploadTransport = TestHTTPTransport(responses: [])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let payload = try compoundResultObject(result)
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["commitAttempted"] == .bool(false))
        #expect(payload["automaticDeletionAttempted"] == .bool(true))
        #expect(payload["parentDeleted"] == .bool(true))
        #expect(requests.map(\.httpMethod) == [
            "GET", "POST", "GET", "GET", "POST", "GET", "DELETE"
        ])
        #expect(!requests.contains { $0.httpMethod == "PATCH" })
        #expect(await uploadTransport.requestCount() == 0)
    }

    @Test("after PATCH starts the compound workflow never auto-deletes parent or child")
    func ambiguousCommitRetainsEveryResource() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: [])),
            .init(statusCode: 201, body: compoundBuildUploadResponse(id: "upload-owned")),
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: ["upload-owned"])),
            .init(statusCode: 200, body: compoundBuildUploadFilesList(ids: [], parentID: "upload-owned")),
            .init(
                statusCode: 201,
                body: compoundBuildUploadFileResponse(
                    id: "file-owned",
                    fileName: fileURL.lastPathComponent,
                    includeUploadOperation: true
                )
            ),
            .init(
                statusCode: 200,
                body: compoundBuildUploadFilesList(
                    ids: ["file-owned"],
                    parentID: "upload-owned",
                    fileName: fileURL.lastPathComponent,
                    includeUploadOperation: true
                )
            ),
            .init(statusCode: 500, body: compoundAPIError(status: 500)),
            .init(
                statusCode: 200,
                body: compoundBuildUploadFileResponse(
                    id: "file-owned",
                    fileName: fileURL.lastPathComponent
                )
            )
        ])
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, headers: ["ETag": "response-etag"], body: "")
        ])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let payload = try compoundResultObject(result)
        let cleanup = try compoundValueObject(payload["cleanup"])
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["operationCommitState"] == .string("unknown"))
        #expect(payload["automaticDeletionAttempted"] == .bool(false))
        #expect(payload["buildUploadId"] == .string("upload-owned"))
        #expect(payload["fileId"] == .string("file-owned"))
        #expect(cleanup["tool"] == nil)
        #expect(cleanup["arguments"] == nil)
        #expect(cleanup["inspectTool"] == .string("build_uploads_get"))
        #expect(requests.map(\.httpMethod) == [
            "GET", "POST", "GET", "GET", "POST", "GET", "PATCH", "GET"
        ])
        #expect(!requests.contains { $0.httpMethod == "DELETE" })
        #expect(await uploadTransport.requestCount() == 1)
    }

    @Test("a definitively rejected PATCH still never triggers automatic deletion")
    func rejectedCommitRetainsEveryResource() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: [])),
            .init(statusCode: 201, body: compoundBuildUploadResponse(id: "upload-owned")),
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: ["upload-owned"])),
            .init(statusCode: 200, body: compoundBuildUploadFilesList(ids: [], parentID: "upload-owned")),
            .init(
                statusCode: 201,
                body: compoundBuildUploadFileResponse(
                    id: "file-owned",
                    fileName: fileURL.lastPathComponent,
                    includeUploadOperation: true
                )
            ),
            .init(
                statusCode: 200,
                body: compoundBuildUploadFilesList(
                    ids: ["file-owned"],
                    parentID: "upload-owned",
                    fileName: fileURL.lastPathComponent,
                    includeUploadOperation: true
                )
            ),
            .init(statusCode: 422, body: compoundAPIError(status: 422))
        ])
        let uploadTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: "")
        ])
        let worker = try await compoundWorker(
            apiTransport: apiTransport,
            uploadTransport: uploadTransport
        )

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let payload = try compoundResultObject(result)
        let cleanup = try compoundValueObject(payload["cleanup"])
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(payload["operationCommitState"] == .string("rejected"))
        #expect(payload["automaticDeletionAttempted"] == .bool(false))
        #expect(cleanup["status"] == .string("not_attempted"))
        #expect(cleanup["tool"] == nil)
        #expect(requests.map(\.httpMethod) == [
            "GET", "POST", "GET", "GET", "POST", "GET", "PATCH"
        ])
        #expect(!requests.contains { $0.httpMethod == "DELETE" })
        #expect(await uploadTransport.requestCount() == 1)
    }

    @Test("recovery rejects a repeated next link before a create request")
    func repeatedRecoveryLinkStopsTraversal() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let repeatedNext = try compoundParentRecoveryNextURL(cursor: "repeat")
        let apiTransport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: [], next: repeatedNext)),
            .init(statusCode: 200, body: compoundBuildUploadsList(ids: [], next: repeatedNext))
        ])
        let worker = try await compoundWorker(apiTransport: apiTransport)

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(!requests.contains { $0.httpMethod == "POST" || $0.httpMethod == "DELETE" })
    }

    @Test("recovery reads at most twenty pages before a create request")
    func recoveryHasTwentyPageCap() async throws {
        let fileURL = try compoundTemporaryUploadFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        var responses: [TestHTTPTransport.Response] = []
        for index in 0..<20 {
            responses.append(.init(
                statusCode: 200,
                body: compoundBuildUploadsList(
                    ids: [],
                    next: try compoundParentRecoveryNextURL(cursor: "page-\(index + 1)")
                )
            ))
        }
        let apiTransport = TestHTTPTransport(responses: responses)
        let worker = try await compoundWorker(apiTransport: apiTransport)

        let result = try await worker.handleTool(compoundUploadParameters(fileURL: fileURL))
        let requests = await apiTransport.recordedRequests()

        #expect(result.isError == true)
        #expect(requests.count == 20)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(!requests.contains { $0.httpMethod == "POST" || $0.httpMethod == "DELETE" })
    }
}

private func compoundWorker(
    apiTransport: any HTTPTransport,
    uploadTransport: (any HTTPTransport)? = nil
) async throws -> BuildUploadsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: apiTransport,
        maxRetries: 1
    )
    return BuildUploadsWorker(
        httpClient: client,
        uploadService: UploadService(transport: uploadTransport, batchSize: 1),
        pollAttempts: 1,
        pollIntervalNanoseconds: 0,
        maxTransferAttempts: 1,
        transferRetryDelayNanoseconds: 0
    )
}

private func compoundUploadParameters(fileURL: URL) -> CallTool.Parameters {
    .init(
        name: "build_uploads_upload",
        arguments: [
            "app_id": .string("app-1"),
            "file_path": .string(fileURL.path),
            "short_version": .string("2.4.0"),
            "build_version": .string("240"),
            "platform": .string("IOS"),
            "asset_type": .string("ASSET"),
            "uti": .string("com.apple.ipa"),
            "max_transfer_attempts": .int(1)
        ]
    )
}

private func compoundTemporaryUploadFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("asc-compound-upload-\(UUID().uuidString).ipa")
    try Data([0, 1, 2]).write(to: url, options: .atomic)
    return url
}

private func compoundBuildUploadResource(
    id: String,
    state: String = "AWAITING_UPLOAD",
    buildID: String? = nil
) -> String {
    let relationships = buildID.map {
        #", "relationships":{"build":{"data":{"type":"builds","id":"\#($0)"}}}"#
    } ?? ""
    return #"{"type":"buildUploads","id":"\#(id)","attributes":{"cfBundleShortVersionString":"2.4.0","cfBundleVersion":"240","platform":"IOS","state":{"state":"\#(state)","errors":[],"warnings":[],"infos":[]}}\#(relationships)}"#
}

private func compoundBuildUploadResponse(
    id: String,
    state: String = "AWAITING_UPLOAD",
    buildID: String? = nil
) -> String {
    #"{"data":\#(compoundBuildUploadResource(id: id, state: state, buildID: buildID)),"links":{"self":"https://api.example.test/v1/buildUploads/\#(id)"}}"#
}

private func compoundBuildUploadsList(ids: [String], next: String? = nil) -> String {
    let resources = ids.map { compoundBuildUploadResource(id: $0) }.joined(separator: ",")
    let nextValue = next.map { #", "next":"\#($0)""# } ?? ""
    return #"{"data":[\#(resources)],"links":{"self":"https://api.example.test/v1/apps/app-1/buildUploads"\#(nextValue)}}"#
}

private func compoundBuildUploadFileResource(
    id: String,
    fileName: String,
    state: String = "AWAITING_UPLOAD",
    includeUploadOperation: Bool = false,
    includeDeliveryState: Bool = true,
    fileChecksum: String? = nil,
    fileChecksumAlgorithm: String = "MD5",
    uploadPath: String = "/build"
) -> String {
    let deliveryState = includeDeliveryState
        ? #""assetDeliveryState":{"state":"\#(state)","errors":[],"warnings":[]},"#
        : ""
    let operation = includeUploadOperation
        ? #", "assetToken":"asset-token-secret","uploadOperations":[{"method":"PUT","url":"https://upload.example.test\#(uploadPath)","length":3,"offset":0,"requestHeaders":[{"name":"X-Upload-Receipt","value":"receipt-value"}],"expiration":"2099-07-20T12:00:00Z","partNumber":1,"entityTag":"apple-etag"}]"#
        : ""
    let checksum = fileChecksum.map {
        #", "sourceFileChecksums":{"file":{"hash":"\#($0)","algorithm":"\#(fileChecksumAlgorithm)"}}"#
    } ?? ""
    return #"{"type":"buildUploadFiles","id":"\#(id)","attributes":{\#(deliveryState)"assetType":"ASSET","fileName":"\#(fileName)","fileSize":3,"uti":"com.apple.ipa"\#(operation)\#(checksum)}}"#
}

private func compoundBuildUploadFileResponse(
    id: String,
    fileName: String,
    state: String = "AWAITING_UPLOAD",
    includeUploadOperation: Bool = false,
    includeDeliveryState: Bool = true,
    fileChecksum: String? = nil,
    fileChecksumAlgorithm: String = "MD5",
    uploadPath: String = "/build"
) -> String {
    #"{"data":\#(compoundBuildUploadFileResource(id: id, fileName: fileName, state: state, includeUploadOperation: includeUploadOperation, includeDeliveryState: includeDeliveryState, fileChecksum: fileChecksum, fileChecksumAlgorithm: fileChecksumAlgorithm, uploadPath: uploadPath)),"links":{"self":"https://api.example.test/v1/buildUploadFiles/\#(id)"}}"#
}

private func compoundBuildUploadFilesList(
    ids: [String],
    parentID: String,
    fileName: String = "unused.ipa",
    next: String? = nil,
    state: String = "AWAITING_UPLOAD",
    includeUploadOperation: Bool = false,
    includeDeliveryState: Bool = true,
    fileChecksum: String? = nil,
    fileChecksumAlgorithm: String = "MD5",
    uploadPath: String = "/build"
) -> String {
    let resources = ids.map {
        compoundBuildUploadFileResource(
            id: $0,
            fileName: fileName,
            state: state,
            includeUploadOperation: includeUploadOperation,
            includeDeliveryState: includeDeliveryState,
            fileChecksum: fileChecksum,
            fileChecksumAlgorithm: fileChecksumAlgorithm,
            uploadPath: uploadPath
        )
    }.joined(separator: ",")
    let nextValue = next.map { #", "next":"\#($0)""# } ?? ""
    return #"{"data":[\#(resources)],"links":{"self":"https://api.example.test/v1/buildUploads/\#(parentID)/buildUploadFiles"\#(nextValue)}}"#
}

private func compoundParentRecoveryNextURL(cursor: String) throws -> String {
    var components = try #require(URLComponents(string: "https://api.example.test/v1/apps/app-1/buildUploads"))
    components.queryItems = [
        URLQueryItem(name: "filter[cfBundleShortVersionString]", value: "2.4.0"),
        URLQueryItem(name: "filter[cfBundleVersion]", value: "240"),
        URLQueryItem(name: "filter[platform]", value: "IOS"),
        URLQueryItem(name: "fields[buildUploads]", value: defaultBuildUploadFields),
        URLQueryItem(name: "limit", value: "200"),
        URLQueryItem(name: "cursor", value: cursor)
    ]
    return try #require(components.url?.absoluteString)
}

private func compoundAPIError(status: Int) -> String {
    #"{"errors":[{"status":"\#(status)","code":"TEST_ERROR","title":"Test error","detail":"Test failure"}]}"#
}

private func compoundResultObject(_ result: CallTool.Result) throws -> [String: Value] {
    try compoundValueObject(result.structuredContent)
}

private func compoundValueObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object)? = value else {
        throw BuildUploadsCompoundTestError.expectedObject
    }
    return object
}

private func compoundValueArray(_ value: Value?) throws -> [Value] {
    guard case .array(let values)? = value else {
        throw BuildUploadsCompoundTestError.expectedArray
    }
    return values
}

private func compoundJSONObject(_ data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw BuildUploadsCompoundTestError.expectedObject
    }
    return object
}

private func compoundJSONObject(_ value: Any?) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
        throw BuildUploadsCompoundTestError.expectedObject
    }
    return object
}

private func compoundValueContains(_ value: Value?, _ needle: String) -> Bool {
    guard let value else { return false }
    switch value {
    case .string(let string):
        return string.contains(needle)
    case .array(let values):
        return values.contains { compoundValueContains($0, needle) }
    case .object(let object):
        return object.contains { key, child in
            key.contains(needle) || compoundValueContains(child, needle)
        }
    default:
        return false
    }
}

private actor CompoundSuccessfulAPITransport: HTTPTransport {
    enum Scenario: Sendable {
        case compound
        case resume
        case alreadyComplete(checksum: String?)
    }

    private let scenario: Scenario
    private let fileName: String
    private var requests: [URLRequest] = []
    private var parentCollectionGetCount = 0
    private var fileCollectionGetCount = 0
    private var parentGetCount = 0
    private var fileGetCount = 0

    init(scenario: Scenario, fileName: String) {
        self.scenario = scenario
        self.fileName = fileName
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let method = request.httpMethod ?? ""
        let path = request.url?.path ?? ""
        let statusCode: Int
        let body: String

        switch (method, path) {
        case ("GET", "/v1/apps/app-1/buildUploads"):
            guard case .compound = scenario else { throw unexpected(method, path) }
            parentCollectionGetCount += 1
            statusCode = 200
            body = compoundBuildUploadsList(
                ids: parentCollectionGetCount == 1 ? [] : ["upload-owned"]
            )
        case ("POST", "/v1/buildUploads"):
            guard case .compound = scenario else { throw unexpected(method, path) }
            statusCode = 201
            body = compoundBuildUploadResponse(id: "upload-owned")
        case ("GET", "/v1/buildUploads/upload-owned/buildUploadFiles"):
            fileCollectionGetCount += 1
            statusCode = 200
            switch scenario {
            case .compound:
                body = compoundBuildUploadFilesList(
                    ids: fileCollectionGetCount == 1 ? [] : ["file-owned"],
                    parentID: "upload-owned",
                    fileName: fileName,
                    includeUploadOperation: fileCollectionGetCount > 1
                )
            case .resume, .alreadyComplete:
                body = compoundBuildUploadFilesList(
                    ids: ["file-owned"],
                    parentID: "upload-owned",
                    fileName: fileName
                )
            }
        case ("POST", "/v1/buildUploadFiles"):
            guard case .compound = scenario else { throw unexpected(method, path) }
            statusCode = 201
            body = compoundBuildUploadFileResponse(
                id: "file-owned",
                fileName: fileName,
                includeUploadOperation: true,
                uploadPath: "/response-only"
            )
        case ("PATCH", "/v1/buildUploadFiles/file-owned"):
            if case .alreadyComplete = scenario {
                throw unexpected(method, path)
            }
            statusCode = 200
            body = compoundBuildUploadFileResponse(
                id: "file-owned",
                fileName: fileName,
                state: "UPLOAD_COMPLETE"
            )
        case ("GET", "/v1/buildUploadFiles/file-owned"):
            fileGetCount += 1
            statusCode = 200
            if case .resume = scenario, fileGetCount == 1 {
                body = compoundBuildUploadFileResponse(
                    id: "file-owned",
                    fileName: fileName,
                    includeUploadOperation: true
                )
            } else if case .alreadyComplete(let checksum) = scenario {
                body = compoundBuildUploadFileResponse(
                    id: "file-owned",
                    fileName: fileName,
                    state: "UPLOAD_COMPLETE",
                    fileChecksum: checksum
                )
            } else {
                body = compoundBuildUploadFileResponse(
                    id: "file-owned",
                    fileName: fileName,
                    state: "UPLOAD_COMPLETE"
                )
            }
        case ("GET", "/v1/buildUploads/upload-owned"):
            parentGetCount += 1
            statusCode = 200
            switch scenario {
            case .compound:
                body = compoundBuildUploadResponse(
                    id: "upload-owned",
                    state: "COMPLETE",
                    buildID: "build-1"
                )
            case .resume, .alreadyComplete:
                if parentGetCount == 1 {
                    body = compoundBuildUploadResponse(id: "upload-owned")
                } else {
                    body = compoundBuildUploadResponse(
                        id: "upload-owned",
                        state: "COMPLETE",
                        buildID: "build-1"
                    )
                }
            }
        default:
            throw unexpected(method, path)
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.test")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        return (Data(body.utf8), response)
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        throw unexpected(request.httpMethod ?? "", request.url?.path ?? "")
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }

    private func unexpected(_ method: String, _ path: String) -> ASCError {
        ASCError.network("Unexpected compound test request: \(method) \(path)")
    }
}

private enum BuildUploadsCompoundTestError: Error {
    case expectedObject
    case expectedArray
}
