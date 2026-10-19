import Foundation
import Testing
@testable import asc_mcp

@Suite("Pinned Asset Upload Transport", .timeLimit(.minutes(1)))
struct AssetPinnedUploadTransportTests {
    @Test("public custom transports and nested response wrappers cannot bypass asset pinning")
    func customTransportCannotBypassPinning() async throws {
        let file = try fixtureFile(Data([1, 2, 3]))
        defer { removeFixture(file) }
        let custom = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        let service = UploadService(transport: custom)
            .withResponseLimit(maxBytes: 64).withResponseLimit(maxBytes: 32)
            .withPinnedDestinations([:])
        let operations = try JSONDecoder().decode([ASCUploadOperation].self, from: Data(#"[{"method":"PUT","url":"https://upload.example.test/file","offset":0,"length":3}]"#.utf8))
        await #expect(throws: ASCError.self) {
            _ = try await service.uploadFile(filePath: file.path, uploadOperations: operations)
        }
        #expect(await custom.requestCount() == 0)
    }

    @Test("configuration pins DNS while retaining the signed URL and TLS hostname")
    func pinnedConfiguration() throws {
        let file = try fixtureFile(Data([1, 2, 3]), name: "quoted\"\\file.bin")
        defer { removeFixture(file) }
        var request = uploadRequest("https://upload.example.test/folder/?token=secret%2Fvalue")
        request.setValue("3", forHTTPHeaderField: "Content-Length")
        request.setValue("bytes 0-2/3", forHTTPHeaderField: "Content-Range")
        request.setValue("signed\"\\header", forHTTPHeaderField: "X-Signed")
        let command = try transport().makeCommand(request: request, fileURL: file, maximumBytes: 16)
        let config = String(decoding: command.configuration, as: UTF8.self)
        #expect(command.executableURL.path == "/usr/bin/curl")
        #expect(command.arguments == ["--disable", "--config", "-"])
        #expect(command.environment == ["LC_ALL": "C", "LANG": "C"])
        #expect(!command.arguments.joined().contains("secret"))
        #expect(!command.arguments.joined().contains(file.path))
        #expect(config.contains("resolve = \"upload.example.test:443:[2606:4700:4700::1111],8.8.8.8\""))
        #expect(config.contains("url = \"https://upload.example.test/folder/?token=secret%2Fvalue\""))
        #expect(config.contains("request-target = \"/folder/?token=secret%2Fvalue\""))
        #expect(config.contains("header = \"X-Signed: signed\\\"\\\\header\""))
        #expect(config.contains("header = \"Content-Length: 3\""))
        #expect(config.contains("header = \"Content-Range: bytes 0-2/3\""))
        #expect(config.contains("header = \"Expect:\""))
        #expect(config.contains("proto = \"=https\""))
        #expect(config.contains("proxy = \"\""))
        #expect(config.contains("noproxy = \"*\""))
        #expect(config.contains("retry = \"0\""))
        #expect(!config.contains("location\n"))
        #expect(!config.contains("insecure"))
        #expect(command.maximumOutputBytes == 16 + AssetPinnedUploadTransport.maximumHeaderBytes)
    }

    @Test("unapproved hosts and schemes fail before launching", arguments: [
        "http://upload.example.test/file", "https://other.example.test/file",
        "https://upload.example.test:444/file", "https://user@upload.example.test/file",
        "https://upload.example.test/file#fragment", "https://127.0.0.1/file",
        "https://[2606:4700:4700::1111]/file", "https://upload.example.test./file"
    ])
    func rejectsUnapprovedURL(_ url: String) async throws {
        let file = try fixtureFile(Data([1]))
        defer { removeFixture(file) }
        let recorder = PinnedProcessRecorder()
        let transport = AssetPinnedUploadTransport(validatedAddresses: ["upload.example.test": ["8.8.8.8"]]) { _ in
            recorder.recordInvocation()
            return Data()
        }
        await #expect(throws: ASCError.self) {
            _ = try await transport.upload(for: uploadRequest(url), fromFile: file, maximumBytes: 16)
        }
        #expect(recorder.invocations == 0)
    }

    @Test("every pinned address is numeric and public", arguments: [
        "127.0.0.1", "10.2.3.4", "169.254.169.254", "0.0.0.0", "::1", "fe80::1",
        "fc00::1", "2001:0db8::1", "2002:7f00:1::1", "3fff::1", "::ffff:127.0.0.1",
        "8.8.8.8,127.0.0.1", "8.8.8.8\nurl=\"http://localhost\"", "public.example.test"
    ])
    func rejectsUnsafePin(_ pin: String) throws {
        let file = try fixtureFile(Data([1]))
        defer { removeFixture(file) }
        let transport = AssetPinnedUploadTransport(validatedAddresses: ["upload.example.test": ["8.8.8.8", pin]])
        #expect(throws: ASCError.self) {
            _ = try transport.makeCommand(request: uploadRequest(), fileURL: file, maximumBytes: 1)
        }
    }

    @Test("credential and connection-control headers cannot reach curl", arguments: [
        "Authorization", "Proxy-Authorization", "Cookie", "Cookie2", "Host", "Connection", "Transfer-Encoding", "Expect"
    ])
    func rejectsProhibitedHeader(_ header: String) throws {
        let file = try fixtureFile(Data([1]))
        defer { removeFixture(file) }
        var request = uploadRequest()
        request.setValue("secret", forHTTPHeaderField: header)
        #expect(throws: ASCError.self) {
            _ = try transport().makeCommand(request: request, fileURL: file, maximumBytes: 1)
        }
    }

    @Test("configuration rejects injection, excessive input and mismatched Content-Length")
    func rejectsUnsafeConfiguration() throws {
        let file = try fixtureFile(Data([1, 2, 3]))
        defer { removeFixture(file) }
        for value in ["4", "-3", "3, 3", "three"] {
            var request = uploadRequest()
            request.setValue(value, forHTTPHeaderField: "Content-Length")
            #expect(throws: ASCError.self) { _ = try transport().makeCommand(request: request, fileURL: file, maximumBytes: 1) }
        }
        var oversized = uploadRequest()
        oversized.setValue(String(repeating: "x", count: 65 * 1_024), forHTTPHeaderField: "X-Large")
        #expect(throws: ASCError.self) { _ = try transport().makeCommand(request: oversized, fileURL: file, maximumBytes: 1) }
        var escaped = uploadRequest()
        escaped.setValue(String(repeating: "\\", count: 34 * 1_024), forHTTPHeaderField: "X-Escaped")
        #expect(throws: ASCError.self) { _ = try transport().makeCommand(request: escaped, fileURL: file, maximumBytes: 1) }
        let newlineFile = try fixtureFile(Data([1]), name: "line\nbreak")
        defer { removeFixture(newlineFile) }
        #expect(throws: ASCError.self) { _ = try transport().makeCommand(request: uploadRequest(), fileURL: newlineFile, maximumBytes: 1) }
        #expect(throws: ASCError.self) { _ = try transport().makeCommand(request: uploadRequest(), fileURL: file, maximumBytes: -1) }
        #expect(throws: ASCError.self) { _ = try transport().makeCommand(request: uploadRequest(), fileURL: file, maximumBytes: 65 * 1_024) }
    }

    @Test("upload source must be a private regular file")
    func validatesSource() throws {
        let file = try fixtureFile(Data([1]))
        defer { removeFixture(file) }
        let link = file.deletingLastPathComponent().appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: ASCError.self) { _ = try transport().makeCommand(request: uploadRequest(), fileURL: link, maximumBytes: 1) }
        #expect(throws: ASCError.self) { _ = try transport().makeCommand(request: uploadRequest(), fileURL: file.deletingLastPathComponent(), maximumBytes: 1) }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(throws: ASCError.self) { _ = try transport().makeCommand(request: uploadRequest(), fileURL: file, maximumBytes: 1) }
    }

    @Test("interim headers are skipped and the final response retains status, body, and ETag")
    func parsesInterimResponse() throws {
        let output = Data(("HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 103 Early Hints\r\nX-Hint: yes\r\n\r\n"
            + "HTTP/1.1 200 OK\r\nContent-Length: 3\r\nETag: etag-value\r\n\r\nabc").utf8)
        let (data, response) = try AssetPinnedUploadTransport.parseResponse(output, url: uploadRequest().url!, maximumBodyBytes: 3)
        #expect(data == Data("abc".utf8))
        #expect(response.statusCode == 200)
        #expect(response.value(forHTTPHeaderField: "ETag") == "etag-value")
        #expect(response.value(forHTTPHeaderField: "X-Hint") == nil)
        #expect(response.url == uploadRequest().url)
    }

    @Test("zero response budget accepts a complete empty response")
    func emptyResponse() throws {
        let (data, response) = try AssetPinnedUploadTransport.parseResponse(
            Data("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n".utf8),
            url: uploadRequest().url!, maximumBodyBytes: 0)
        #expect(data.isEmpty)
        #expect(response.statusCode == 204)
    }

    @Test("redirect and error statuses are returned without following them", arguments: [307, 401, 429, 503])
    func preservesStatus(_ status: Int) async throws {
        let file = try fixtureFile(Data([1]))
        defer { removeFixture(file) }
        let recorder = PinnedProcessRecorder()
        let transport = AssetPinnedUploadTransport(validatedAddresses: ["upload.example.test": ["8.8.8.8"]]) { _ in
            recorder.recordInvocation()
            return Data("HTTP/1.1 \(status) Status\r\nLocation: https://other.example.test/secret\r\nContent-Length: 0\r\n\r\n".utf8)
        }
        let (data, response) = try await transport.upload(for: uploadRequest(), fromFile: file, maximumBytes: 0)
        #expect(data.isEmpty)
        #expect(response.statusCode == status)
        #expect(response.url == uploadRequest().url)
        #expect(recorder.invocations == 1)
    }

    @Test("response budgets and invalid response framing fail closed")
    func rejectsInvalidResponses() throws {
        let responses = [
            "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nabcd",
            "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nabc",
            "HTTP/1.1 200 OK\r\nContent-Length: 3\r\ncontent-length: 3\r\n\r\nabc",
            "HTTP/1.1 200 OK\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\nabc",
            "HTTP/1.1 200 OK\r\nInvalid header\r\n\r\n",
            "HTTP/1.1 101 Switching Protocols\r\n\r\n",
            "HTTP/1.1 200 OK\r\nX-Header: incomplete",
            String(repeating: "HTTP/1.1 100 Continue\r\n\r\n", count: 10),
            "HTTP/1.1 200 OK\r\n" + String(repeating: "X-Header: x\r\n", count: 129) + "\r\n",
            "HTTP/1.1 200 OK\r\nX-Large: " + String(repeating: "x", count: 64 * 1_024) + "\r\n\r\n",
        ]
        for response in responses {
            #expect(throws: ASCError.self) {
                _ = try AssetPinnedUploadTransport.parseResponse(Data(response.utf8), url: uploadRequest().url!, maximumBodyBytes: 3)
            }
        }
    }

    @Test("transport errors expose no raw process diagnostics")
    func sanitizedFailure() async throws {
        let file = try fixtureFile(Data([1]))
        defer { removeFixture(file) }
        let transport = AssetPinnedUploadTransport(validatedAddresses: ["upload.example.test": ["8.8.8.8"]]) { _ in
            throw ASCError.network("private-token https://upload.example.test/?signature=secret")
        }
        do {
            _ = try await transport.upload(for: uploadRequest(), fromFile: file, maximumBytes: 1)
            Issue.record("Expected the injected upload failure")
        } catch {
            #expect(!error.localizedDescription.contains("private-token"))
            #expect(!error.localizedDescription.contains("signature"))
        }
    }

    @Test("cancelled callers never invoke the process runner")
    func cancellationBeforeStart() async throws {
        let file = try fixtureFile(Data([1]))
        defer { removeFixture(file) }
        let recorder = PinnedProcessRecorder()
        let transport = AssetPinnedUploadTransport(validatedAddresses: ["upload.example.test": ["8.8.8.8"]]) { _ in
            recorder.recordInvocation()
            return Data()
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.upload(for: uploadRequest(), fromFile: file, maximumBytes: 1)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(recorder.invocations == 0)
    }

    @Test("process output is streamed within the combined byte budget without networking")
    func boundedProcessOutput() async throws {
        let output = try fixtureFile(Data(repeating: 120, count: 512 * 1_024))
        defer { removeFixture(output) }
        let recorder = PinnedProcessRecorder()
        let command = AssetPinnedUploadCommand(configuration: Data(), maximumOutputBytes: 64, timeout: 3)
        await #expect(throws: ASCError.self) {
            _ = try await AssetPinnedUploadProcess.run(command) { process in
                process.executableURL = URL(fileURLWithPath: "/bin/cat")
                process.arguments = [output.path]
                try process.run()
                recorder.recordProcess(process)
            }
        }
        #expect(recorder.processHasExited)
    }

    @Test("process runner drains and reaps a successful child without networking")
    func successfulProcessOutput() async throws {
        let body = Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n".utf8)
        let output = try fixtureFile(body)
        defer { removeFixture(output) }
        let recorder = PinnedProcessRecorder()
        let command = AssetPinnedUploadCommand(configuration: Data(), maximumOutputBytes: body.count, timeout: 3)
        let received = try await AssetPinnedUploadProcess.run(command) { process in
            process.executableURL = URL(fileURLWithPath: "/bin/cat")
            process.arguments = [output.path]
            try process.run()
            recorder.recordProcess(process)
        }
        #expect(received == body)
        #expect(recorder.processHasExited)
    }

    @Test("cancellation terminates and reaps the active child without networking")
    func processCancellation() async throws {
        let recorder = PinnedProcessRecorder()
        let command = AssetPinnedUploadCommand(configuration: Data(), maximumOutputBytes: 16, timeout: 5)
        let task = Task {
            try await AssetPinnedUploadProcess.run(command) { process in
                process.executableURL = URL(fileURLWithPath: "/bin/sleep")
                process.arguments = ["30"]
                try process.run()
                recorder.recordProcess(process)
            }
        }
        defer { task.cancel() }
        for _ in 0..<200 {
            if recorder.invocations > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(recorder.invocations == 1)
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(recorder.processHasExited)
    }

    @Test("watchdog terminates a stuck child independently of curl's timeout")
    func processWatchdog() async throws {
        let recorder = PinnedProcessRecorder()
        let command = AssetPinnedUploadCommand(configuration: Data(), maximumOutputBytes: 16, timeout: 0.05)
        await #expect(throws: ASCError.self) {
            _ = try await AssetPinnedUploadProcess.run(command) { process in
                process.executableURL = URL(fileURLWithPath: "/bin/sleep")
                process.arguments = ["30"]
                try process.run()
                recorder.recordProcess(process)
            }
        }
        #expect(recorder.processHasExited)
    }

    private func transport() -> AssetPinnedUploadTransport {
        AssetPinnedUploadTransport(validatedAddresses: ["upload.example.test": ["8.8.8.8", "2606:4700:4700::1111"]])
    }

    private func uploadRequest(_ value: String = "https://upload.example.test/file?signature=secret") -> URLRequest {
        var request = URLRequest(url: URL(string: value)!)
        request.httpMethod = "PUT"
        return request
    }

    private func fixtureFile(_ data: Data, name: String = "upload.bin") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("asc-pinned-transport-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent(name)
        try data.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file
    }

    private func removeFixture(_ file: URL) { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
}

private final class PinnedProcessRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var process: Process?

    var invocations: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    var processHasExited: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process.map { !$0.isRunning } ?? false
    }

    func recordInvocation() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }

    func recordProcess(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        self.process = process
    }
}
