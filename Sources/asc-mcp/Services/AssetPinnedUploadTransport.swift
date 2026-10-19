import Foundation
import Darwin

struct AssetPinnedUploadCommand: Sendable {
    let configuration: Data
    let maximumOutputBytes: Int
    let timeout: TimeInterval
    let executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    let arguments = ["--disable", "--config", "-"]
    let environment = ["LC_ALL": "C", "LANG": "C"]
}

/// Uploads asset snapshots using macOS `/usr/bin/curl` and previously verified public addresses.
/// The system curl executable is required; no fallback transport or DNS lookup is permitted.
struct AssetPinnedUploadTransport: HTTPTransport {
    static let maximumHeaderBytes = 64 * 1_024
    static let maximumBodyBytes = 64 * 1_024
    static let maximumHeaderCount = 128

    private let validatedAddresses: [String: [String]]
    private let execute: @Sendable (AssetPinnedUploadCommand) async throws -> Data

    init(validatedAddresses: [String: [String]],
         execute: @escaping @Sendable (AssetPinnedUploadCommand) async throws -> Data = AssetPinnedUploadProcess.run) {
        self.validatedAddresses = validatedAddresses
        self.execute = execute
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw ASCError.network("The pinned asset transport only accepts file uploads")
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        try await upload(for: request, fromFile: fileURL, maximumBytes: Self.maximumBodyBytes)
    }

    func upload(for request: URLRequest, fromFile fileURL: URL, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let command = try makeCommand(request: request, fileURL: fileURL, maximumBytes: maximumBytes)
        let output: Data
        do {
            output = try await execute(command)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw ASCError.network("Pinned asset upload failed; no automatic retry was attempted")
        }
        try Task.checkCancellation()
        guard output.count <= command.maximumOutputBytes, let url = request.url else {
            throw ASCError.network("Pinned upload response exceeded its byte limit")
        }
        return try Self.parseResponse(output, url: url, maximumBodyBytes: maximumBytes)
    }

    func makeCommand(request: URLRequest, fileURL: URL, maximumBytes: Int) throws -> AssetPinnedUploadCommand {
        guard (0...Self.maximumBodyBytes).contains(maximumBytes),
              let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.user == nil, components.password == nil,
              components.fragment == nil, components.port == nil || components.port == 443,
              let host = components.host?.lowercased(), Self.validHostname(host),
              components.percentEncodedHost?.lowercased() == host,
              let pins = validatedAddresses[host], !pins.isEmpty, pins.count <= 32,
              let method = request.httpMethod, ["PUT", "POST"].contains(method),
              request.httpBody == nil, request.httpBodyStream == nil,
              url.absoluteString.utf8.count <= 32 * 1_024 else {
            throw ASCError.network("Upload requires HTTPS, a pinned DNS hostname, a supported method and a bounded response")
        }
        let addresses = try Set(pins.map(Self.canonicalPublicAddress)).sorted()
        let resolve = host + ":443:" + addresses.map { $0.contains(":") ? "[\($0)]" : $0 }.joined(separator: ",")
        let size = try Self.checkedFileSize(fileURL)
        let target = (components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath)
            + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        var options = [
            "silent", "globoff", "http1.1", "path-as-is", "include",
            "proto = \"=https\"", "proto-redir = \"=https\"", "proxy = \"\"", "noproxy = \"*\"",
            "retry = \"0\"", "connect-timeout = \"30\"", "max-time = \"300\"", "max-redirs = \"0\"", "header = \"Expect:\"",
            "url = \(try Self.quoted(url.absoluteString))",
            "request = \(try Self.quoted(method))",
            "request-target = \(try Self.quoted(target))",
            "resolve = \(try Self.quoted(resolve))",
            "upload-file = \(try Self.quoted(fileURL.path))",
            "output = \"-\""
        ]
        let headers = request.allHTTPHeaderFields ?? [:]
        guard headers.count <= Self.maximumHeaderCount else { throw ASCError.network("Too many upload request headers") }
        var headerBytes = 0
        for (name, value) in headers.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
            let lower = name.lowercased()
            guard Self.validHeaderName(name), Self.safeValue(value),
                  !["authorization", "proxy-authorization", "cookie", "cookie2", "host", "connection", "transfer-encoding", "expect"].contains(lower) else {
                throw ASCError.network("Upload contains a prohibited request header")
            }
            headerBytes += name.utf8.count + value.utf8.count
            guard headerBytes <= Self.maximumHeaderBytes else { throw ASCError.network("Upload request headers exceed the byte limit") }
            if lower == "content-length" {
                guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }), Int64(value) == size else {
                    throw ASCError.network("Upload Content-Length does not match the local snapshot")
                }
            }
            options.append("header = \(try Self.quoted(value.isEmpty ? name + ";" : name + ": " + value))")
        }
        let configuration = Data((options.joined(separator: "\n") + "\n").utf8)
        guard configuration.count <= 64 * 1_024 else { throw ASCError.network("Upload configuration exceeds the byte limit") }
        return AssetPinnedUploadCommand(configuration: configuration,
                                        maximumOutputBytes: maximumBytes + Self.maximumHeaderBytes, timeout: 305)
    }

    static func parseResponse(_ output: Data, url: URL, maximumBodyBytes: Int) throws -> (Data, HTTPURLResponse) {
        guard (0...Self.maximumBodyBytes).contains(maximumBodyBytes),
              output.count <= maximumBodyBytes + maximumHeaderBytes else {
            throw ASCError.network("Upload response exceeded its byte limit")
        }
        let separator = Data([13, 10, 13, 10])
        var remaining = output
        var totalHeaderBytes = 0
        var totalHeaders = 0
        for _ in 0..<9 {
            guard let boundary = remaining.range(of: separator) else { throw ASCError.network("Upload response headers are incomplete") }
            let headerEnd = boundary.upperBound
            totalHeaderBytes += remaining.distance(from: remaining.startIndex, to: headerEnd)
            guard totalHeaderBytes <= maximumHeaderBytes,
                  let text = String(data: remaining[..<boundary.lowerBound], encoding: .isoLatin1) else {
                throw ASCError.network("Upload response headers exceeded their byte limit")
            }
            let lines = text.components(separatedBy: "\r\n")
            let statusParts = lines[0].split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard statusParts.count >= 2, ["HTTP/1.0", "HTTP/1.1"].contains(String(statusParts[0])),
                  statusParts[1].count == 3, let status = Int(statusParts[1]), (100...599).contains(status) else {
                throw ASCError.network("Upload returned an invalid HTTP status line")
            }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { throw ASCError.network("Upload returned an invalid HTTP header") }
                let name = String(line[..<colon])
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                guard validHeaderName(name), safeValue(value) else { throw ASCError.network("Upload returned an invalid HTTP header") }
                totalHeaders += 1
                guard totalHeaders <= maximumHeaderCount else { throw ASCError.network("Upload response has too many headers") }
                let key = name.lowercased()
                if let previous = headers[key] {
                    guard key != "content-length" else { throw ASCError.network("Upload response has duplicate Content-Length headers") }
                    headers[key] = previous + ", " + value
                } else { headers[key] = value }
            }
            remaining = Data(remaining[headerEnd...])
            if status < 200 {
                guard status != 101 else { throw ASCError.network("Upload protocol switching is prohibited") }
                continue
            }
            guard remaining.count <= maximumBodyBytes else { throw ASCError.network("Upload response body exceeded its byte limit") }
            if let length = headers["content-length"] {
                guard !length.isEmpty, length.utf8.allSatisfy({ (48...57).contains($0) }),
                      let count = Int(length), count == remaining.count, headers["transfer-encoding"] == nil else {
                    throw ASCError.network("Upload response body does not match its Content-Length")
                }
            }
            guard let response = HTTPURLResponse(url: url, statusCode: status,
                                                httpVersion: String(statusParts[0]), headerFields: headers) else {
                throw ASCError.network("Upload response metadata could not be decoded")
            }
            return (remaining, response)
        }
        throw ASCError.network("Upload returned too many interim responses")
    }

    private static func quoted(_ value: String) throws -> String {
        guard safeValue(value) else { throw ASCError.network("Upload configuration contains prohibited control characters") }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func safeValue(_ value: String) -> Bool {
        !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }

    private static func validHeaderName(_ value: String) -> Bool {
        let token = Set("!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
        return !value.isEmpty && value.utf8.allSatisfy { token.contains($0) }
    }

    private static func validHostname(_ host: String) -> Bool {
        let characters = Set("abcdefghijklmnopqrstuvwxyz0123456789-".utf8)
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return host.utf8.count <= 253 && host.utf8.contains(where: { (97...122).contains($0) })
            && labels.count >= 2 && labels.allSatisfy { label in
                !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                    && label.utf8.allSatisfy { characters.contains($0) }
            } && host != "localhost" && !host.hasSuffix(".localhost") && !host.hasSuffix(".local")
    }

    private static func canonicalPublicAddress(_ value: String) throws -> String {
        guard !value.contains("%"), value.utf8.count <= Int(INET6_ADDRSTRLEN) else {
            throw ASCError.network("Upload pin is not a supported public address")
        }
        var address4 = in_addr()
        var address6 = in6_addr()
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let normalized: String
        if value.withCString({ inet_pton(AF_INET, $0, &address4) }) == 1 {
            guard inet_ntop(AF_INET, &address4, &buffer, socklen_t(buffer.count)) != nil else { throw ASCError.network("Invalid upload address") }
        } else if value.withCString({ inet_pton(AF_INET6, $0, &address6) }) == 1 {
            guard inet_ntop(AF_INET6, &address6, &buffer, socklen_t(buffer.count)) != nil else { throw ASCError.network("Invalid upload address") }
        } else { throw ASCError.network("Upload pin must be a numeric IP address") }
        normalized = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard AssetUploadDestinationPolicy.isPublicAddress(normalized) else { throw ASCError.network("Upload pin points to a prohibited network address") }
        return normalized
    }

    private static func checkedFileSize(_ fileURL: URL) throws -> Int64 {
        guard fileURL.isFileURL, fileURL.path.hasPrefix("/"), !fileURL.path.contains("\0") else {
            throw ASCError.network("Upload requires an absolute local snapshot path")
        }
        let descriptor = open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw ASCError.network("Upload snapshot is unavailable") }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              info.st_size > 0, info.st_size <= AssetMediaInspector.maximumFileSize else {
            throw ASCError.network("Upload snapshot must be a private regular file within the size limit")
        }
        return Int64(info.st_size)
    }
}

final class AssetPinnedUploadProcess: @unchecked Sendable {
    private enum Failure: Equatable { case cancelled, timedOut, oversized, io }
    private let lock = NSLock()
    private var process: Process?
    private var failure: Failure?

    static func run(_ command: AssetPinnedUploadCommand) async throws -> Data {
        try await run(command, launch: { try $0.run() })
    }

    static func run(_ command: AssetPinnedUploadCommand,
                    launch: @escaping @Sendable (Process) throws -> Void) async throws -> Data {
        let execution = AssetPinnedUploadProcess()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try execution.runSynchronously(command, launch: launch)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { execution.stop(.cancelled) }
    }

    private func runSynchronously(_ command: AssetPinnedUploadCommand,
                                  launch: @Sendable (Process) throws -> Void) throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: command.executableURL.path) else {
            throw ASCError.network("Asset uploads require the system /usr/bin/curl executable")
        }
        let child = Process()
        let input = Pipe()
        let output = Pipe()
        child.executableURL = command.executableURL
        child.arguments = command.arguments
        child.environment = command.environment
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        child.currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw ASCError.network("Cannot safely configure the upload process input")
        }
        defer {
            try? input.fileHandleForReading.close()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            withState { self.process = nil }
        }
        try withState {
            if failure == .cancelled { throw CancellationError() }
            process = child
        }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + command.timeout)
        timer.setEventHandler { [weak self] in self?.stop(.timedOut) }
        timer.resume()
        defer { timer.cancel() }
        do { try launch(child) }
        catch { throw ASCError.network("Cannot start the system asset upload transport") }
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        if withState({ failure != nil }) { stopChild(child) }
        var bytes = Data()
        do {
            try input.fileHandleForWriting.write(contentsOf: command.configuration)
            try input.fileHandleForWriting.close()
            while let chunk = try output.fileHandleForReading.read(upToCount: 16 * 1_024), !chunk.isEmpty {
                guard chunk.count <= command.maximumOutputBytes - bytes.count else {
                    stop(.oversized)
                    break
                }
                bytes.append(chunk)
            }
        } catch { stop(.io) }
        child.waitUntilExit()
        let problem = withState { failure }
        if problem == .cancelled { throw CancellationError() }
        guard problem == nil, child.terminationReason == .exit, child.terminationStatus == 0 else {
            throw ASCError.network("System asset upload failed or exceeded its response/time limit")
        }
        return bytes
    }

    private func stop(_ reason: Failure) {
        let child = withState {
            if failure == nil { failure = reason }
            return process
        }
        if let child { stopChild(child) }
    }

    private func stopChild(_ child: Process) {
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
    }

    private func withState<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
