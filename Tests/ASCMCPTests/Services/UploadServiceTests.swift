import Foundation
import Testing
@testable import asc_mcp

@Suite("Upload Service Tests")
struct UploadServiceTests {
    @Test("rejects invalid upload ranges")
    func rejectsInvalidRanges() async throws {
        let service = UploadService(transport: RecordingUploadTransport(), batchSize: 3)
        let fileURL = try makeTempFile(bytes: (0..<10).map(UInt8.init))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: ASCError.self) {
            _ = try await service.uploadFile(
                filePath: fileURL.path,
                uploadOperations: [
                    ASCUploadOperation(
                        method: "PUT",
                        url: "https://upload.example.test/too-long",
                        length: 20,
                        offset: 0,
                        requestHeaders: nil
                    )
                ]
            )
        }
    }

    @Test("rejects incomplete and overlapping byte coverage")
    func rejectsInvalidCoverage() async throws {
        let cases: [[ASCUploadOperation]] = [
            [],
            [
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/zero", length: 0, offset: 0, requestHeaders: nil)
            ],
            [
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/0", length: 4, offset: 0, requestHeaders: nil),
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/1", length: 5, offset: 5, requestHeaders: nil)
            ],
            [
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/0", length: 6, offset: 0, requestHeaders: nil),
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/1", length: 5, offset: 5, requestHeaders: nil)
            ],
            [
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/0", length: 5, offset: 0, requestHeaders: nil),
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/duplicate", length: 5, offset: 0, requestHeaders: nil),
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/1", length: 5, offset: 5, requestHeaders: nil)
            ]
        ]

        for operations in cases {
            let transport = RecordingUploadTransport()
            let service = UploadService(transport: transport, batchSize: 3)
            let fileURL = try makeTempFile(bytes: (0..<10).map(UInt8.init))
            defer { try? FileManager.default.removeItem(at: fileURL) }

            await #expect(throws: ASCError.self) {
                _ = try await service.uploadFile(
                    filePath: fileURL.path,
                    uploadOperations: operations
                )
            }
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("rejects unsafe upload URLs", arguments: [
        "http://upload.example.test/chunk",
        "https://user:password@upload.example.test/chunk",
        "https://upload.example.test/chunk#fragment"
    ])
    func rejectsUnsafeUploadURL(_ url: String) async throws {
        let transport = RecordingUploadTransport()
        let service = UploadService(transport: transport, batchSize: 1)
        let fileURL = try makeTempFile(bytes: [0, 1, 2])
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: ASCError.self) {
            _ = try await service.uploadFile(
                filePath: fileURL.path,
                uploadOperations: [
                    ASCUploadOperation(
                        method: "PUT",
                        url: url,
                        length: 3,
                        offset: 0,
                        requestHeaders: nil
                    )
                ]
            )
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("accepts unordered exact coverage without reordering execution")
    func acceptsUnorderedExactCoverage() async throws {
        let transport = RecordingUploadTransport()
        let service = UploadService(transport: transport, batchSize: 1)
        let fileURL = try makeTempFile(bytes: (0..<9).map(UInt8.init))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        _ = try await service.uploadFile(
            filePath: fileURL.path,
            uploadOperations: [
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/2", length: 3, offset: 6, requestHeaders: nil),
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/0", length: 3, offset: 0, requestHeaders: nil),
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/1", length: 3, offset: 3, requestHeaders: nil)
            ]
        )

        #expect(await transport.recordedPaths() == ["/2", "/0", "/1"])
    }

    @Test("uploads exact byte ranges")
    func uploadsExactByteRanges() async throws {
        let transport = RecordingUploadTransport()
        let service = UploadService(transport: transport, batchSize: 3)
        let fileURL = try makeTempFile(bytes: (0..<9).map(UInt8.init))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        _ = try await service.uploadFile(
            filePath: fileURL.path,
            uploadOperations: [
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/0", length: 3, offset: 0, requestHeaders: nil),
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/1", length: 3, offset: 3, requestHeaders: nil),
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/2", length: 3, offset: 6, requestHeaders: nil)
            ]
        )

        let bodies = await transport.bodiesByPath()
        #expect(bodies["/0"] == Data([0, 1, 2]))
        #expect(bodies["/1"] == Data([3, 4, 5]))
        #expect(bodies["/2"] == Data([6, 7, 8]))
    }

    @Test("uploads large exact ranges from files without using data transport")
    func uploadsLargeRangesFromFiles() async throws {
        let byteCount = (2 * 1024 * 1024) + 37
        let bytes = (0..<byteCount).map { UInt8($0 % 251) }
        let firstLength = (1024 * 1024) + 17
        let transport = RecordingUploadTransport()
        let service = UploadService(transport: transport, batchSize: 1)
        let fileURL = try makeTempFile(bytes: bytes)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        _ = try await service.uploadFile(
            filePath: fileURL.path,
            uploadOperations: [
                ASCUploadOperation(
                    method: "PUT",
                    url: "https://upload.example.test/0",
                    length: firstLength,
                    offset: 0,
                    requestHeaders: nil
                ),
                ASCUploadOperation(
                    method: "PUT",
                    url: "https://upload.example.test/1",
                    length: byteCount - firstLength,
                    offset: firstLength,
                    requestHeaders: nil
                )
            ]
        )

        let bodies = await transport.bodiesByPath()
        let uploadedPaths = await transport.uploadedFilePaths()
        let uploadedPermissions = await transport.uploadedFilePermissions()
        #expect(await transport.dataRequestCount() == 0)
        #expect(await transport.requestsWithHTTPBodyCount() == 0)
        #expect(bodies["/0"] == Data(bytes[0..<firstLength]))
        #expect(bodies["/1"] == Data(bytes[firstLength..<byteCount]))
        #expect(uploadedPermissions.allSatisfy { $0 & 0o777 == 0o600 })
        #expect(uploadedPaths.allSatisfy {
            URL(fileURLWithPath: $0).lastPathComponent.hasPrefix("asc-mcp-upload-chunk-")
        })
        #expect(uploadedPaths.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
    }

    @Test("removes temporary chunk file after transfer failure")
    func removesChunkAfterTransferFailure() async throws {
        let transport = FailingFileUploadTransport(behavior: .failure)
        let service = UploadService(transport: transport, batchSize: 1)
        let fileURL = try makeTempFile(bytes: [0, 1, 2, 3, 4, 5])
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: ASCError.self) {
            _ = try await service.uploadFile(
                filePath: fileURL.path,
                uploadOperations: [
                    ASCUploadOperation(method: "PUT", url: "https://upload.example.test/0", length: 3, offset: 0, requestHeaders: nil),
                    ASCUploadOperation(method: "PUT", url: "https://upload.example.test/1", length: 3, offset: 3, requestHeaders: nil)
                ]
            )
        }

        let uploadedPaths = await transport.uploadedFilePaths()
        #expect(await transport.dataRequestCount() == 0)
        #expect(uploadedPaths.count == 1)
        #expect(uploadedPaths.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
    }

    @Test("removes temporary chunk file after cancellation")
    func removesChunkAfterCancellation() async throws {
        let transport = FailingFileUploadTransport(behavior: .cancellation)
        let service = UploadService(transport: transport, batchSize: 1)
        let fileURL = try makeTempFile(bytes: [0, 1, 2, 3, 4, 5])
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await service.uploadFile(
                filePath: fileURL.path,
                uploadOperations: [
                    ASCUploadOperation(method: "PUT", url: "https://upload.example.test/0", length: 3, offset: 0, requestHeaders: nil),
                    ASCUploadOperation(method: "PUT", url: "https://upload.example.test/1", length: 3, offset: 3, requestHeaders: nil)
                ]
            )
            Issue.record("Expected upload cancellation")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        let uploadedPaths = await transport.uploadedFilePaths()
        #expect(await transport.dataRequestCount() == 0)
        #expect(uploadedPaths.count == 1)
        #expect(uploadedPaths.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
    }

    @Test("source mutation cannot change uploaded bytes or committed checksum")
    func sourceMutationUsesImmutableSnapshot() async throws {
        let original = Data([0, 1, 2, 3, 4, 5])
        let replacement = Data([9, 9, 9, 9, 9, 9])
        let fileURL = try makeTempFile(bytes: Array(original))
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let transport = SourceMutatingUploadTransport(
            sourceURL: fileURL,
            replacement: replacement
        )
        let service = UploadService(transport: transport, batchSize: 1)

        let checksum = try await service.uploadFile(
            filePath: fileURL.path,
            uploadOperations: [
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/0", length: 3, offset: 0, requestHeaders: nil),
                ASCUploadOperation(method: "PUT", url: "https://upload.example.test/1", length: 3, offset: 3, requestHeaders: nil)
            ]
        )

        let bodies = await transport.bodiesByPath()
        let expectedChecksum = await service.computeMD5(data: original)
        let currentSource = try Data(contentsOf: fileURL)
        #expect(bodies["/0"] == Data([0, 1, 2]))
        #expect(bodies["/1"] == Data([3, 4, 5]))
        #expect(checksum == expectedChecksum)
        #expect(currentSource == replacement)
    }

    @Test("limits upload concurrency to batch size")
    func limitsConcurrency() async throws {
        let transport = RecordingUploadTransport(responseDelayNanoseconds: 40_000_000)
        let service = UploadService(transport: transport, batchSize: 3)
        let fileURL = try makeTempFile(bytes: (0..<12).map(UInt8.init))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        _ = try await service.uploadFile(
            filePath: fileURL.path,
            uploadOperations: (0..<6).map { index in
                ASCUploadOperation(
                    method: "PUT",
                    url: "https://upload.example.test/\(index)",
                    length: 2,
                    offset: index * 2,
                    requestHeaders: nil
                )
            }
        )

        #expect(await transport.maximumConcurrentRequests() <= 3)
        #expect(await transport.requestCount() == 6)
    }

    @Test("streaming MD5 matches full-data hash")
    func streamingMD5MatchesFullDataHash() async throws {
        let bytes = Array(0..<128).map(UInt8.init)
        let fileURL = try makeTempFile(bytes: bytes)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let service = UploadService()

        let streamingHash = try await service.computeMD5(fileURL: fileURL)
        let fullHash = await service.computeMD5(data: Data(bytes))

        #expect(streamingHash == fullHash)
    }

    private func makeTempFile(bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-mcp-upload-\(UUID().uuidString).bin")
        try Data(bytes).write(to: url)
        return url
    }
}

private actor RecordingUploadTransport: HTTPTransport {
    private var requestBodies: [String: Data] = [:]
    private var paths: [String] = []
    private var uploadedPaths: [String] = []
    private var uploadFileModes: [Int] = []
    private var dataRequests = 0
    private var requestsWithHTTPBody = 0
    private var activeRequests = 0
    private var maxActiveRequests = 0
    private let responseDelayNanoseconds: UInt64

    init(responseDelayNanoseconds: UInt64 = 0) {
        self.responseDelayNanoseconds = responseDelayNanoseconds
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        dataRequests += 1
        return try await respond(to: request, body: request.httpBody ?? Data())
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        uploadedPaths.append(fileURL.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        uploadFileModes.append(permissions)
        let body = try Data(contentsOf: fileURL)
        return try await respond(to: request, body: body)
    }

    private func respond(to request: URLRequest, body: Data) async throws -> (Data, HTTPURLResponse) {
        activeRequests += 1
        maxActiveRequests = max(maxActiveRequests, activeRequests)
        defer { activeRequests -= 1 }

        if responseDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: responseDelayNanoseconds)
        }

        let path = request.url?.path ?? ""
        paths.append(path)
        requestBodies[path] = body
        if request.httpBody != nil {
            requestsWithHTTPBody += 1
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://upload.example.test")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(), response)
    }

    func bodiesByPath() -> [String: Data] {
        requestBodies
    }

    func maximumConcurrentRequests() -> Int {
        maxActiveRequests
    }

    func requestCount() -> Int {
        paths.count
    }

    func recordedPaths() -> [String] {
        paths
    }

    func uploadedFilePaths() -> [String] {
        uploadedPaths
    }

    func uploadedFilePermissions() -> [Int] {
        uploadFileModes
    }

    func dataRequestCount() -> Int {
        dataRequests
    }

    func requestsWithHTTPBodyCount() -> Int {
        requestsWithHTTPBody
    }
}

private actor SourceMutatingUploadTransport: HTTPTransport {
    private let sourceURL: URL
    private let replacement: Data
    private var didMutate = false
    private var requestBodies: [String: Data] = [:]

    init(sourceURL: URL, replacement: Data) {
        self.sourceURL = sourceURL
        self.replacement = replacement
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw ASCError.network("SourceMutatingUploadTransport only supports file uploads")
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        if !didMutate {
            try replacement.write(to: sourceURL, options: .atomic)
            didMutate = true
        }

        requestBodies[request.url?.path ?? ""] = try Data(contentsOf: fileURL)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://upload.example.test")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(), response)
    }

    func bodiesByPath() -> [String: Data] {
        requestBodies
    }
}

private actor FailingFileUploadTransport: HTTPTransport {
    enum Behavior: Sendable {
        case failure
        case cancellation
    }

    private let behavior: Behavior
    private var uploadedPaths: [String] = []
    private var dataRequests = 0

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        dataRequests += 1
        throw ASCError.network("Unexpected data transport call")
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        uploadedPaths.append(fileURL.path)
        switch behavior {
        case .failure:
            throw ASCError.network("Simulated file upload failure")
        case .cancellation:
            withUnsafeCurrentTask { $0?.cancel() }
            throw CancellationError()
        }
    }

    func uploadedFilePaths() -> [String] {
        uploadedPaths
    }

    func dataRequestCount() -> Int {
        dataRequests
    }
}
