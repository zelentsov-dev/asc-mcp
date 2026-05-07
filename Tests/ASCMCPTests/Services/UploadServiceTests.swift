import Foundation
import Testing
@testable import asc_mcp

@Suite("Upload Service Tests")
struct UploadServiceTests {
    @Test("rejects invalid upload ranges")
    func rejectsInvalidRanges() async throws {
        let service = UploadService(transport: RecordingUploadTransport(), batchSize: 3)
        let fileURL = try makeTempFile(bytes: (0..<10).map(UInt8.init))

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

    @Test("uploads exact byte ranges")
    func uploadsExactByteRanges() async throws {
        let transport = RecordingUploadTransport()
        let service = UploadService(transport: transport, batchSize: 3)
        let fileURL = try makeTempFile(bytes: (0..<9).map(UInt8.init))

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

    @Test("limits upload concurrency to batch size")
    func limitsConcurrency() async throws {
        let transport = RecordingUploadTransport(responseDelayNanoseconds: 40_000_000)
        let service = UploadService(transport: transport, batchSize: 3)
        let fileURL = try makeTempFile(bytes: (0..<12).map(UInt8.init))

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
    private var activeRequests = 0
    private var maxActiveRequests = 0
    private let responseDelayNanoseconds: UInt64

    init(responseDelayNanoseconds: UInt64 = 0) {
        self.responseDelayNanoseconds = responseDelayNanoseconds
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        activeRequests += 1
        maxActiveRequests = max(maxActiveRequests, activeRequests)
        defer { activeRequests -= 1 }

        if responseDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: responseDelayNanoseconds)
        }

        requestBodies[request.url?.path ?? ""] = request.httpBody ?? Data()
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
        requestBodies.count
    }
}
