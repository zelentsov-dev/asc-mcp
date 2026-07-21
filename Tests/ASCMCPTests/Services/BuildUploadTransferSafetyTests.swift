import Foundation
import Testing
@testable import asc_mcp

@Suite("Build Upload Transfer Safety Tests")
struct BuildUploadTransferSafetyTests {
    @Test("only explicit PUT retries and receipts omit presigned secrets")
    func explicitPUTRetriesWithoutLeakingSecrets() async throws {
        let transport = BuildUploadScriptedTransport(stepsByPath: [
            "/upload": [
                .failure,
                .response(statusCode: 503),
                .response(statusCode: 200, headers: ["ETag": "response-etag"])
            ]
        ])
        let service = UploadService(transport: transport, batchSize: 1)
        let fileURL = try makeTempFile(bytes: [0, 1, 2])
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let snapshot = try await service.prepareSnapshot(filePath: fileURL.path)
        defer { snapshot.discard() }

        let result = try await service.uploadFileWithReceipts(
            snapshot: snapshot,
            uploadOperations: [
                ASCUploadOperation(
                    method: "PUT",
                    url: "https://upload.example.test/upload?signature=query-secret",
                    length: 3,
                    offset: 0,
                    requestHeaders: [
                        ASCUploadRequestHeader(name: "X-Upload-Signature", value: "header-secret")
                    ],
                    expiration: "2099-07-20T12:00:00Z",
                    partNumber: 1,
                    entityTag: "apple-etag"
                )
            ],
            maxAttemptsPerPart: 3,
            retryDelayNanoseconds: 0
        )

        let receipt = try #require(result.receipts.first)
        #expect(receipt.attempts == 3)
        #expect(receipt.statusCode == 200)
        #expect(receipt.responseEntityTag == "response-etag")
        #expect(result.fileMD5 == snapshot.md5Checksum)
        #expect(await transport.requestCount(for: "/upload") == 3)

        let requests = await transport.recordedRequests()
        #expect(requests.allSatisfy { $0.httpMethod == "PUT" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "X-Upload-Signature") == "header-secret"
        })

        let labels = Mirror(reflecting: receipt).children.compactMap(\.label)
        #expect(labels.allSatisfy { !$0.lowercased().contains("url") })
        #expect(labels.allSatisfy { !$0.lowercased().contains("header") })
        let renderedReceipt = String(reflecting: receipt)
        #expect(!renderedReceipt.contains("query-secret"))
        #expect(!renderedReceipt.contains("header-secret"))
        #expect(!renderedReceipt.contains("upload.example.test"))
    }

    @Test("non-exact PUT methods never retry transient status")
    func nonIdempotentAndImplicitMethodsDoNotRetryStatus() async throws {
        let methods: [String?] = ["POST", "PATCH", nil, "X-APPLE-UPLOAD", "put", "Put", "pUt"]

        for method in methods {
            let transport = BuildUploadScriptedTransport(stepsByPath: [
                "/upload": [
                    .response(statusCode: 503),
                    .response(statusCode: 200)
                ]
            ])
            let service = UploadService(transport: transport, batchSize: 1)
            let fileURL = try makeTempFile(bytes: [0, 1, 2])
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let snapshot = try await service.prepareSnapshot(filePath: fileURL.path)
            defer { snapshot.discard() }

            do {
                _ = try await service.uploadFileWithReceipts(
                    snapshot: snapshot,
                    uploadOperations: [
                        ASCUploadOperation(
                            method: method,
                            url: "https://upload.example.test/upload",
                            length: 3,
                            offset: 0,
                            requestHeaders: nil
                        )
                    ],
                    maxAttemptsPerPart: 3,
                    retryDelayNanoseconds: 0
                )
                Issue.record("Expected transfer failure for method \(method ?? "nil")")
            } catch let failure as UploadTransferFailure {
                #expect(failure.message == "Upload chunk 0 failed with status 503")
                #expect(failure.receipts.isEmpty)
            } catch {
                Issue.record("Expected UploadTransferFailure, got \(error)")
            }

            #expect(await transport.requestCount(for: "/upload") == 1)
            #expect(await transport.recordedMethods() == [(method ?? "PUT").uppercased()])
        }
    }

    @Test("non-exact PUT methods never retry transport failure")
    func nonIdempotentAndImplicitMethodsDoNotRetryTransportFailure() async throws {
        let methods: [String?] = ["POST", "PATCH", nil, "X-APPLE-UPLOAD", "put", "Put", "pUt"]

        for method in methods {
            let transport = BuildUploadScriptedTransport(stepsByPath: [
                "/upload": [.failure, .response(statusCode: 200)]
            ])
            let service = UploadService(transport: transport, batchSize: 1)
            let fileURL = try makeTempFile(bytes: [0, 1, 2])
            defer { try? FileManager.default.removeItem(at: fileURL) }
            let snapshot = try await service.prepareSnapshot(filePath: fileURL.path)
            defer { snapshot.discard() }

            do {
                _ = try await service.uploadFileWithReceipts(
                    snapshot: snapshot,
                    uploadOperations: [
                        ASCUploadOperation(
                            method: method,
                            url: "https://upload.example.test/upload",
                            length: 3,
                            offset: 0,
                            requestHeaders: nil
                        )
                    ],
                    maxAttemptsPerPart: 3,
                    retryDelayNanoseconds: 0
                )
                Issue.record("Expected transfer failure for method \(method ?? "nil")")
            } catch let failure as UploadTransferFailure {
                #expect(failure.message == "Upload chunk 0 transfer failed")
                #expect(failure.receipts.isEmpty)
            } catch {
                Issue.record("Expected UploadTransferFailure, got \(error)")
            }

            #expect(await transport.requestCount(for: "/upload") == 1)
            #expect(await transport.recordedMethods() == [(method ?? "PUT").uppercased()])
        }
    }

    @Test("cancellation after confirmed 200 preserves the receipt")
    func cancellationAfterConfirmedResponsePreservesReceipt() async throws {
        let transport = BuildUploadCancellationGateTransport(behaviorsByPath: [
            "/confirmed": .confirmedSuccess
        ])
        let service = UploadService(transport: transport, batchSize: 1)
        let fileURL = try makeTempFile(bytes: [0, 1, 2])
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let snapshot = try await service.prepareSnapshot(filePath: fileURL.path)
        defer { snapshot.discard() }
        let operations = [
            ASCUploadOperation(
                method: "PUT",
                url: "https://upload.example.test/confirmed",
                length: 3,
                offset: 0,
                requestHeaders: nil,
                partNumber: 1
            )
        ]

        let transferTask = Task<BuildUploadTaskOutcome, Never> {
            await captureBuildUploadOutcome(
                service: service,
                snapshot: snapshot,
                operations: operations
            )
        }
        await transport.waitForRequestCount(1)
        transferTask.cancel()
        await transport.releaseAll()

        switch await transferTask.value {
        case .transferFailure(let failure):
            #expect(failure.message == "Upload checksum verification was cancelled after byte transfer completed")
            #expect(failure.receipts.count == 1)
            #expect(failure.receipts.first?.operationIndex == 0)
            #expect(failure.receipts.first?.statusCode == 200)
        case .cancelled:
            Issue.record("Confirmed HTTP 200 must not become a bare CancellationError")
        case .success(_):
            Issue.record("Expected checksum cancellation after the confirmed transfer")
        case .unexpected(let message):
            Issue.record("Unexpected transfer error: \(message)")
        }
    }

    @Test("mixed batch cancellation preserves the confirmed receipt")
    func mixedBatchCancellationPreservesConfirmedReceipt() async throws {
        let transport = BuildUploadCancellationGateTransport(behaviorsByPath: [
            "/confirmed": .confirmedSuccess,
            "/cancelled": .observeCancellation
        ])
        let service = UploadService(transport: transport, batchSize: 2)
        let fileURL = try makeTempFile(bytes: [0, 1, 2, 3, 4, 5])
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let snapshot = try await service.prepareSnapshot(filePath: fileURL.path)
        defer { snapshot.discard() }
        let operations = [
            ASCUploadOperation(
                method: "PUT",
                url: "https://upload.example.test/confirmed",
                length: 3,
                offset: 0,
                requestHeaders: nil,
                partNumber: 1
            ),
            ASCUploadOperation(
                method: "PUT",
                url: "https://upload.example.test/cancelled",
                length: 3,
                offset: 3,
                requestHeaders: nil,
                partNumber: 2
            )
        ]

        let transferTask = Task<BuildUploadTaskOutcome, Never> {
            await captureBuildUploadOutcome(
                service: service,
                snapshot: snapshot,
                operations: operations
            )
        }
        await transport.waitForRequestCount(2)
        transferTask.cancel()
        await transport.releaseAll()

        switch await transferTask.value {
        case .transferFailure(let failure):
            #expect(failure.message == "Upload was cancelled before all parts completed")
            #expect(failure.receipts.count == 1)
            #expect(failure.receipts.first?.operationIndex == 0)
            #expect(failure.receipts.first?.partNumber == 1)
            #expect(failure.receipts.first?.statusCode == 200)
        case .cancelled:
            Issue.record("Mixed batch cancellation must preserve confirmed receipts")
        case .success(_):
            Issue.record("Expected the incomplete mixed batch to fail")
        case .unexpected(let message):
            Issue.record("Unexpected transfer error: \(message)")
        }
    }

    @Test("redirect policy refuses signed request forwarding")
    func redirectPolicyRefusesSignedRequestForwarding() {
        let delegate = PresignedUploadRedirectDelegate()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let originalRequest = URLRequest(url: URL(string: "https://upload.example.test/upload")!)
        let task = session.dataTask(with: originalRequest)
        defer { task.cancel() }
        let redirectResponse = HTTPURLResponse(
            url: originalRequest.url!,
            statusCode: 307,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": "https://redirect.example.test/upload"]
        )!
        var redirectedRequest = URLRequest(url: URL(string: "https://redirect.example.test/upload")!)
        redirectedRequest.setValue("signed-secret", forHTTPHeaderField: "X-Upload-Signature")
        let completion = BuildUploadRedirectCompletion()

        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: redirectResponse,
            newRequest: redirectedRequest
        ) { request in
            completion.record(request)
        }

        let result = completion.result()
        #expect(result.called)
        #expect(result.request == nil)
    }

    @Test("a followed redirect response is rejected without a receipt")
    func followedRedirectResponseIsRejected() async throws {
        let transport = BuildUploadRedirectingTransport()
        let service = UploadService(transport: transport, batchSize: 1)
        let fileURL = try makeTempFile(bytes: [0, 1, 2])
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let snapshot = try await service.prepareSnapshot(filePath: fileURL.path)
        defer { snapshot.discard() }

        do {
            _ = try await service.uploadFileWithReceipts(
                snapshot: snapshot,
                uploadOperations: [
                    ASCUploadOperation(
                        method: "PUT",
                        url: "https://upload.example.test/upload?signature=query-secret",
                        length: 3,
                        offset: 0,
                        requestHeaders: [
                            ASCUploadRequestHeader(name: "X-Upload-Signature", value: "header-secret")
                        ]
                    )
                ],
                maxAttemptsPerPart: 3,
                retryDelayNanoseconds: 0
            )
            Issue.record("Expected redirect rejection")
        } catch let failure as UploadTransferFailure {
            #expect(failure.message == "Upload chunk 0 redirect response was rejected")
            #expect(failure.receipts.isEmpty)
            #expect(!failure.localizedDescription.contains("query-secret"))
            #expect(!failure.localizedDescription.contains("header-secret"))
        } catch {
            Issue.record("Expected UploadTransferFailure, got \(error)")
        }

        #expect(await transport.requestCount() == 1)
    }

    @Test("invalid multipart metadata and expired URLs fail before transfer")
    func invalidMultipartMetadataFailsBeforeTransfer() async throws {
        let transport = BuildUploadScriptedTransport(stepsByPath: [:])
        let service = UploadService(transport: transport, batchSize: 1)
        let fileURL = try makeTempFile(bytes: [0, 1, 2])
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let invalidOperations = [
            ASCUploadOperation(
                method: "PUT",
                url: "https://upload.example.test/upload",
                length: 3,
                offset: 0,
                requestHeaders: nil,
                expiration: "not-a-date",
                partNumber: 1
            ),
            ASCUploadOperation(
                method: "PUT",
                url: "https://upload.example.test/upload",
                length: 3,
                offset: 0,
                requestHeaders: nil,
                partNumber: 0
            ),
            ASCUploadOperation(
                method: "PUT",
                url: "https://upload.example.test/upload",
                length: 3,
                offset: 0,
                requestHeaders: nil,
                partNumber: 9_007_199_254_740_992
            )
        ]

        for operation in invalidOperations {
            await #expect(throws: ASCError.self) {
                _ = try await service.uploadFile(
                    filePath: fileURL.path,
                    uploadOperations: [operation]
                )
            }
        }

        do {
            _ = try await service.uploadFile(
                filePath: fileURL.path,
                uploadOperations: [
                    ASCUploadOperation(
                        method: "PUT",
                        url: "https://upload.example.test/upload",
                        length: 3,
                        offset: 0,
                        requestHeaders: nil,
                        expiration: "2000-01-01T00:00:00Z",
                        partNumber: 1
                    )
                ]
            )
            Issue.record("Expected expired URL failure")
        } catch let error as ASCError {
            #expect(error.localizedDescription == "Network error: Upload chunk 0 URL has expired")
        } catch {
            Issue.record("Expected ASCError, got \(error)")
        }

        #expect(await transport.recordedRequests().isEmpty)
    }

    @Test("a later expired operation prevents every presigned transfer")
    func laterExpiredOperationFailsGlobalPreflight() async throws {
        let formatter = ISO8601DateFormatter()
        let now = Date()
        let transport = BuildUploadScriptedTransport(stepsByPath: [
            "/valid": [.response(statusCode: 200)]
        ])
        let service = UploadService(transport: transport, batchSize: 2)
        let fileURL = try makeTempFile(bytes: [0, 1, 2, 3, 4, 5])
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let snapshot = try await service.prepareSnapshot(filePath: fileURL.path)
        defer { snapshot.discard() }

        do {
            _ = try await service.uploadFileWithReceipts(
                snapshot: snapshot,
                uploadOperations: [
                    ASCUploadOperation(
                        method: "PUT",
                        url: "https://upload.example.test/valid",
                        length: 3,
                        offset: 0,
                        requestHeaders: nil,
                        expiration: formatter.string(from: now.addingTimeInterval(3_600)),
                        partNumber: 1
                    ),
                    ASCUploadOperation(
                        method: "PUT",
                        url: "https://upload.example.test/expired",
                        length: 3,
                        offset: 3,
                        requestHeaders: nil,
                        expiration: formatter.string(from: now.addingTimeInterval(-3_600)),
                        partNumber: 2
                    )
                ],
                maxAttemptsPerPart: 1,
                retryDelayNanoseconds: 0
            )
            Issue.record("Expected global expiration preflight failure")
        } catch let error as ASCError {
            #expect(error.localizedDescription == "Network error: Upload chunk 1 URL has expired")
        } catch let failure as UploadTransferFailure {
            #expect(failure.receipts.isEmpty)
            Issue.record("Expected validation failure before receipt tracking")
        } catch {
            Issue.record("Expected ASCError, got \(error)")
        }

        #expect(await transport.recordedRequests().isEmpty)
    }

    @Test("same batch failure preserves only completed redaction-safe receipts")
    func sameBatchFailurePreservesCompletedReceipts() async throws {
        let transport = BuildUploadScriptedTransport(stepsByPath: [
            "/success": [.response(statusCode: 200)],
            "/failure": [.response(statusCode: 400)]
        ])
        let service = UploadService(transport: transport, batchSize: 2)
        let fileURL = try makeTempFile(bytes: [0, 1, 2, 3, 4, 5])
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let snapshot = try await service.prepareSnapshot(filePath: fileURL.path)
        defer { snapshot.discard() }

        do {
            _ = try await service.uploadFileWithReceipts(
                snapshot: snapshot,
                uploadOperations: [
                    ASCUploadOperation(method: "PUT", url: "https://upload.example.test/success", length: 3, offset: 0, requestHeaders: nil, partNumber: 1),
                    ASCUploadOperation(method: "PUT", url: "https://upload.example.test/failure", length: 3, offset: 3, requestHeaders: nil, partNumber: 2)
                ],
                maxAttemptsPerPart: 1,
                retryDelayNanoseconds: 0
            )
            Issue.record("Expected transfer failure")
        } catch let failure as UploadTransferFailure {
            #expect(failure.receipts.count == 1)
            #expect(failure.receipts.first?.operationIndex == 0)
            #expect(failure.receipts.first?.partNumber == 1)
        } catch {
            Issue.record("Expected UploadTransferFailure, got \(error)")
        }
    }

    @Test("snapshot keeps 0600 permissions and detects post-transfer mutation")
    func snapshotPermissionsAndMutationGuard() async throws {
        let service = UploadService(transport: BuildUploadSnapshotMutatingTransport(), batchSize: 1)
        let fileURL = try makeTempFile(bytes: [0, 1, 2])
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let snapshot = try await service.prepareSnapshot(filePath: fileURL.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: snapshot.url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let computedMD5 = try await service.computeMD5(fileURL: snapshot.url)
        #expect(permissions & 0o777 == 0o600)
        #expect(snapshot.md5Checksum == computedMD5)
        snapshot.discard()

        do {
            _ = try await service.uploadFile(
                filePath: fileURL.path,
                uploadOperations: [
                    ASCUploadOperation(
                        method: "PUT",
                        url: "https://upload.example.test/upload",
                        length: 3,
                        offset: 0,
                        requestHeaders: nil
                    )
                ]
            )
            Issue.record("Expected immutable snapshot guard failure")
        } catch let error as ASCError {
            #expect(error.localizedDescription == "Network error: The immutable upload snapshot changed during transfer")
        } catch {
            Issue.record("Expected ASCError, got \(error)")
        }
    }

    @Test("snapshot read failure after confirmed 200 retains the receipt")
    func snapshotReadFailureAfterConfirmedResponseRetainsReceipt() async throws {
        let service = UploadService(transport: BuildUploadSnapshotRemovingTransport(), batchSize: 1)
        let fileURL = try makeTempFile(bytes: [0, 1, 2])
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let snapshot = try await service.prepareSnapshot(filePath: fileURL.path)
        defer { snapshot.discard() }

        do {
            _ = try await service.uploadFileWithReceipts(
                snapshot: snapshot,
                uploadOperations: [
                    ASCUploadOperation(
                        method: "PUT",
                        url: "https://upload.example.test/upload",
                        length: 3,
                        offset: 0,
                        requestHeaders: nil,
                        partNumber: 1
                    )
                ],
                maxAttemptsPerPart: 1,
                retryDelayNanoseconds: 0
            )
            Issue.record("Expected post-transfer snapshot read failure")
        } catch let failure as UploadTransferFailure {
            #expect(failure.receipts.count == 1)
            #expect(failure.receipts.first?.operationIndex == 0)
            #expect(failure.receipts.first?.statusCode == 200)
            #expect(failure.receipts.first?.partNumber == 1)
            #expect(failure.message.contains("Failed to open file"))
            #expect(!FileManager.default.fileExists(atPath: snapshot.url.path))
        } catch {
            Issue.record("Expected UploadTransferFailure, got \(error)")
        }
    }

    @Test("streaming hash observes task cancellation")
    func streamingHashObservesTaskCancellation() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-mcp-build-upload-hash-\(UUID().uuidString).bin")
        try Data(repeating: 0x5a, count: (3 * 1024 * 1024) + 17).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let service = UploadService()
        let gate = BuildUploadExecutionGate()

        let hashTask = Task<Bool, Never> {
            await gate.waitForRelease()
            do {
                _ = try await service.computeMD5(fileURL: fileURL)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        await gate.waitUntilEntered()
        hashTask.cancel()
        await gate.release()

        #expect(await hashTask.value)
    }

    private func makeTempFile(bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-mcp-build-upload-safety-\(UUID().uuidString).bin")
        try Data(bytes).write(to: url)
        return url
    }
}

private enum BuildUploadTaskOutcome: Sendable {
    case success(UploadTransferResult)
    case transferFailure(UploadTransferFailure)
    case cancelled
    case unexpected(String)
}

private func captureBuildUploadOutcome(
    service: UploadService,
    snapshot: UploadFileSnapshot,
    operations: [ASCUploadOperation]
) async -> BuildUploadTaskOutcome {
    do {
        return .success(
            try await service.uploadFileWithReceipts(
                snapshot: snapshot,
                uploadOperations: operations,
                maxAttemptsPerPart: 1,
                retryDelayNanoseconds: 0
            )
        )
    } catch let failure as UploadTransferFailure {
        return .transferFailure(failure)
    } catch is CancellationError {
        return .cancelled
    } catch {
        return .unexpected(error.localizedDescription)
    }
}

private enum BuildUploadCancellationBehavior: Sendable {
    case confirmedSuccess
    case observeCancellation
}

private actor BuildUploadExecutionGate {
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func waitForRelease() async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
        guard !released else { return }
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll(keepingCapacity: true)
        continuations.forEach { $0.resume() }
    }
}

private actor BuildUploadCancellationGateTransport: HTTPTransport {
    private struct RequestWaiter: Sendable {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let behaviorsByPath: [String: BuildUploadCancellationBehavior]
    private var requestCount = 0
    private var requestWaiters: [RequestWaiter] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
    private var released = false

    init(behaviorsByPath: [String: BuildUploadCancellationBehavior]) {
        self.behaviorsByPath = behaviorsByPath
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw ASCError.network("BuildUploadCancellationGateTransport only supports file uploads")
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        guard let behavior = behaviorsByPath[path] else {
            throw ASCError.network("No cancellation behavior for \(path)")
        }

        requestCount += 1
        notifyRequestWaiters()
        if !released {
            await withCheckedContinuation { continuation in
                releaseContinuations.append(continuation)
            }
        }

        if case .observeCancellation = behavior {
            try Task.checkCancellation()
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://upload.example.test")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(), response)
    }

    func waitForRequestCount(_ count: Int) async {
        guard requestCount < count else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(RequestWaiter(count: count, continuation: continuation))
        }
    }

    func releaseAll() {
        released = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll(keepingCapacity: true)
        continuations.forEach { $0.resume() }
    }

    private func notifyRequestWaiters() {
        var remaining: [RequestWaiter] = []
        var ready: [CheckedContinuation<Void, Never>] = []
        for waiter in requestWaiters {
            if requestCount >= waiter.count {
                ready.append(waiter.continuation)
            } else {
                remaining.append(waiter)
            }
        }
        requestWaiters = remaining
        ready.forEach { $0.resume() }
    }
}

private enum BuildUploadScriptedStep: Sendable {
    case failure
    case response(statusCode: Int, headers: [String: String] = [:])
}

private final class BuildUploadRedirectCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var called = false
    private var request: URLRequest?

    func record(_ request: URLRequest?) {
        lock.lock()
        called = true
        self.request = request
        lock.unlock()
    }

    func result() -> (called: Bool, request: URLRequest?) {
        lock.lock()
        let result = (called, request)
        lock.unlock()
        return result
    }
}

private actor BuildUploadScriptedTransport: HTTPTransport {
    private var stepsByPath: [String: [BuildUploadScriptedStep]]
    private var requests: [URLRequest] = []

    init(stepsByPath: [String: [BuildUploadScriptedStep]]) {
        self.stepsByPath = stepsByPath
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw ASCError.network("BuildUploadScriptedTransport only supports file uploads")
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url?.path ?? ""
        guard var steps = stepsByPath[path], !steps.isEmpty else {
            throw ASCError.network("No scripted response for \(path)")
        }
        let step = steps.removeFirst()
        stepsByPath[path] = steps

        switch step {
        case .failure:
            throw URLError(.timedOut)
        case .response(let statusCode, let headers):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://upload.example.test")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            return (Data(), response)
        }
    }

    func requestCount(for path: String) -> Int {
        requests.filter { $0.url?.path == path }.count
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }

    func recordedMethods() -> [String] {
        requests.compactMap(\.httpMethod)
    }
}

private actor BuildUploadRedirectingTransport: HTTPTransport {
    private var requests = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw ASCError.network("BuildUploadRedirectingTransport only supports file uploads")
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests += 1
        let response = HTTPURLResponse(
            url: URL(string: "https://redirect.example.test/upload")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(), response)
    }

    func requestCount() -> Int {
        requests
    }
}

private actor BuildUploadSnapshotMutatingTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw ASCError.network("BuildUploadSnapshotMutatingTransport only supports file uploads")
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        let byteCount = try Data(contentsOf: fileURL).count
        try Data(repeating: 0xff, count: byteCount).write(to: fileURL)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://upload.example.test")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(), response)
    }
}

private actor BuildUploadSnapshotRemovingTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw ASCError.network("BuildUploadSnapshotRemovingTransport only supports file uploads")
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        try FileManager.default.removeItem(at: fileURL)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://upload.example.test")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(), response)
    }
}
