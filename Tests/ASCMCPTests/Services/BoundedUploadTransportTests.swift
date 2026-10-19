import Foundation
import Testing
@testable import asc_mcp

@Suite("Bounded Upload Response Tests", .serialized, .timeLimit(.minutes(1)))
struct BoundedUploadTransportTests {
    @Test("production bounded uploads preserve exact-limit responses and ETag")
    func exactLimit() async throws {
        let file = try uploadFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = request("exact")
        let (data, response) = try await transport().upload(for: request, fromFile: file, maximumBytes: 16)
        #expect(data == Data(repeating: 7, count: 16))
        #expect(response.statusCode == 200)
        #expect(response.value(forHTTPHeaderField: "ETag") == "test-etag")
        let recorded = BoundedUploadURLProtocol.recorder.requests(for: request.url!)
        #expect(recorded.count == 1)
        #expect(recorded.first?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(recorded.first?.httpMethod == "PUT")
        #expect(recorded.first?.value(forHTTPHeaderField: "X-Upload-Test") == "preserved")
    }

    @Test("unknown-length response is cancelled before the entire stream is consumed")
    func streamingOverflow() async throws {
        let file = try uploadFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = request("stream")
        await #expect(throws: ASCError.self) {
            _ = try await transport().upload(for: request, fromFile: file, maximumBytes: 2_048)
        }
        try await waitForStop(request.url!)
        #expect(BoundedUploadURLProtocol.recorder.bytes(for: request.url!) < 128 * 1_024)
    }

    @Test("oversized advertised bodies and headers are rejected", arguments: ["length", "headerBytes", "headerCount"])
    func rejectsOversizedMetadata(_ mode: String) async throws {
        let file = try uploadFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = request(mode)
        await #expect(throws: ASCError.self) {
            _ = try await transport().upload(for: request, fromFile: file, maximumBytes: 16)
        }
    }

    @Test("bounded production uploads never follow redirects")
    func refusesRedirect() async throws {
        let file = try uploadFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = request("redirect")
        let (_, response) = try await transport().upload(for: request, fromFile: file, maximumBytes: 16)
        #expect(response.statusCode == 307)
        #expect(response.url == request.url)
        let target = BoundedUploadURLProtocol.targetURL(for: request.url!)
        #expect(BoundedUploadURLProtocol.recorder.requests(for: target).isEmpty)
    }

    @Test("task cancellation interrupts an active response")
    func cancellationDuringResponse() async throws {
        let file = try uploadFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = request("hang")
        let transport = transport()
        let task = Task { try await transport.upload(for: request, fromFile: file, maximumBytes: 16) }
        defer { task.cancel() }
        for _ in 0..<200 {
            if !BoundedUploadURLProtocol.recorder.requests(for: request.url!).isEmpty { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!BoundedUploadURLProtocol.recorder.requests(for: request.url!).isEmpty)
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        try await waitForStop(request.url!)
    }

    @Test("an already cancelled caller does not start an upload")
    func cancellationBeforeStart() async throws {
        let file = try uploadFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = request("exact")
        let transport = transport()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.upload(for: request, fromFile: file, maximumBytes: 16)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(BoundedUploadURLProtocol.recorder.requests(for: request.url!).isEmpty)
    }

    @Test("concurrent response limits remain isolated")
    func independentRequests() async throws {
        let file = try uploadFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let transport = transport()
        let accepted = request("exact")
        let rejected = request("stream")
        async let success = transport.upload(for: accepted, fromFile: file, maximumBytes: 16)
        await #expect(throws: ASCError.self) {
            _ = try await transport.upload(for: rejected, fromFile: file, maximumBytes: 1_024)
        }
        let received = try await success
        #expect(received.0 == Data(repeating: 7, count: 16))
    }

    @Test("service response limits are opt-in and mock transports retain source compatibility")
    func serviceOptIn() async throws {
        let file = try uploadFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let transport = ResponseOnlyUploadTransport()
        let original = UploadService(transport: transport, batchSize: 1)
        let bounded = original.withResponseLimit(maxBytes: 2)
        let operation = ASCUploadOperation(method: "PUT", url: "https://upload.example.test/file", length: 3, offset: 0, requestHeaders: nil)
        _ = try await original.uploadFile(filePath: file.path, uploadOperations: [operation])
        await #expect(throws: ASCError.self) {
            _ = try await bounded.uploadFile(filePath: file.path, uploadOperations: [operation])
        }
        _ = try await original.uploadFile(filePath: file.path, uploadOperations: [operation])
        #expect(await transport.calls() == 3)
    }

    @Test("zero response budgets accept empty responses and negative budgets fail before transport")
    func budgetEdges() async throws {
        let file = try uploadFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let (data, _) = try await transport().upload(for: request("zero"), fromFile: file, maximumBytes: 0)
        #expect(data.isEmpty)
        let rejected = request("exact")
        await #expect(throws: ASCError.self) {
            _ = try await transport().upload(for: rejected, fromFile: file, maximumBytes: -1)
        }
        #expect(BoundedUploadURLProtocol.recorder.requests(for: rejected.url!).isEmpty)
    }

    private func request(_ mode: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://bounded-upload.example.test/\(mode)/\(UUID().uuidString)")!)
        request.httpMethod = "PUT"
        request.setValue("preserved", forHTTPHeaderField: "X-Upload-Test")
        return request
    }

    private func transport() -> PresignedUploadURLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundedUploadURLProtocol.self]
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 5
        return PresignedUploadURLSessionTransport(configuration: configuration)
    }

    private func uploadFile() throws -> URL {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../.build/bounded-upload-tests/\(UUID().uuidString)").standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("upload.bin")
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    private func waitForStop(_ url: URL) async throws {
        for _ in 0..<200 {
            if BoundedUploadURLProtocol.recorder.stopped(url) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("The bounded transport did not cancel its URLProtocol request")
    }
}

private actor ResponseOnlyUploadTransport: HTTPTransport {
    private var count = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw ASCError.network("Unexpected data request")
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        count += 1
        return (Data([1, 2, 3]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func calls() -> Int { count }
}

private final class BoundedUploadURLProtocol: URLProtocol, @unchecked Sendable {
    static let recorder = BoundedUploadRecorder()
    private let lock = NSLock()
    private var cancelled = false

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "bounded-upload.example.test"
    }

    override class func canInit(with task: URLSessionTask) -> Bool {
        guard let request = task.currentRequest ?? task.originalRequest else { return false }
        return canInit(with: request)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.recorder.started(request)
        let mode = url.pathComponents[1]
        var headers = ["ETag": "test-etag"]
        if mode == "length" { headers["Content-Length"] = "1000000" }
        if mode == "headerBytes" { headers["X-Oversized"] = String(repeating: "x", count: BoundedUploadSession.maximumHeaderBytes + 1) }
        if mode == "headerCount" {
            for index in 0...BoundedUploadSession.maximumHeaderCount { headers["X-Header-\(index)"] = "x" }
        }
        if mode == "exact" { headers["Content-Length"] = "16" }
        if mode == "zero" { headers["Content-Length"] = "0" }
        let status = mode == "redirect" ? 307 : 200
        if mode == "redirect" { headers["Location"] = Self.targetURL(for: url).absoluteString }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        if mode == "redirect" {
            var redirected = request
            redirected.url = Self.targetURL(for: url)
            client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if mode == "hang" { return }
        if mode == "stream" {
            sendChunk(0)
            return
        }
        if mode == "exact" { client?.urlProtocol(self, didLoad: Data(repeating: 7, count: 16)) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        lock.lock()
        cancelled = true
        lock.unlock()
        if let url = request.url { Self.recorder.stop(url) }
    }

    static func targetURL(for url: URL) -> URL {
        URL(string: "https://bounded-upload.example.test/target/\(url.lastPathComponent)")!
    }

    private func sendChunk(_ index: Int) {
        lock.lock()
        let stopped = cancelled
        lock.unlock()
        guard !stopped else { return }
        if index == 128 {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let data = Data(repeating: 9, count: 1_024)
        if let url = request.url { Self.recorder.addBytes(data.count, for: url) }
        client?.urlProtocol(self, didLoad: data)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(5)) { [self] in sendChunk(index + 1) }
    }
}

private final class BoundedUploadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URL: [URLRequest]] = [:]
    private var received: [URL: Int] = [:]
    private var cancellations: Set<URL> = []

    func started(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        recorded[request.url!, default: []].append(request)
    }

    func requests(for url: URL) -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded[url] ?? []
    }

    func addBytes(_ count: Int, for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        received[url, default: 0] += count
    }

    func bytes(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return received[url] ?? 0
    }

    func stop(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        cancellations.insert(url)
    }

    func stopped(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellations.contains(url)
    }
}
