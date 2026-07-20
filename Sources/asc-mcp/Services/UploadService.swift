import Foundation
import CryptoKit
import os

private enum UploadChunkOutcome: Sendable {
    case success(Int, UploadPartReceipt)
    case failure(Int, String)
    case cancelled
}

final class PresignedUploadRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func redirectedRequest(_ request: URLRequest) -> URLRequest? {
        nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(redirectedRequest(request))
    }
}

final class PresignedUploadURLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let redirectDelegate: PresignedUploadRedirectDelegate
    private let urlSession: URLSession

    init(configuration: URLSessionConfiguration) {
        let redirectDelegate = PresignedUploadRedirectDelegate()
        self.redirectDelegate = redirectDelegate
        self.urlSession = URLSession(configuration: configuration)
    }

    deinit {
        urlSession.invalidateAndCancel()
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await urlSession.data(for: request, delegate: redirectDelegate)
        guard let response = response as? HTTPURLResponse else {
            throw ASCError.network("Invalid response format")
        }
        return (data, response)
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await urlSession.upload(
            for: request,
            fromFile: fileURL,
            delegate: redirectDelegate
        )
        guard let response = response as? HTTPURLResponse else {
            throw ASCError.network("Invalid response format")
        }
        return (data, response)
    }
}

/// Service for uploading assets to App Store Connect
/// Transfers immutable file snapshots with bounded memory after validating HTTPS targets and exact byte coverage.
public actor UploadService {
    private let transport: any HTTPTransport
    private let batchSize: Int
    private let logger = Logger(subsystem: "com.asc-mcp", category: "UploadService")

    public init(transport: (any HTTPTransport)? = nil, batchSize: Int = 3) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.transport = transport ?? PresignedUploadURLSessionTransport(configuration: config)
        self.batchSize = max(1, batchSize)
    }

    /// Uploads an immutable snapshot of a file using the provided upload operations
    /// - Parameters:
    ///   - filePath: Absolute path to the file on disk
    ///   - uploadOperations: Upload operations from the ASC reserve response
    /// - Returns: MD5 hex checksum of the exact snapshot bytes uploaded
    /// - Throws: ASCError on file read, unsafe or incomplete upload operations, or transfer failure
    public func uploadFile(
        filePath: String,
        uploadOperations: [ASCUploadOperation]
    ) async throws -> String {
        let snapshot = try prepareSnapshot(filePath: filePath)
        defer { discardSnapshot(snapshot) }
        return try await uploadFile(snapshot: snapshot, uploadOperations: uploadOperations)
    }

    func prepareSnapshot(filePath: String) throws -> UploadFileSnapshot {
        let sourceURL = URL(fileURLWithPath: filePath)
        let snapshotURL = try createSnapshot(of: sourceURL)
        do {
            return UploadFileSnapshot(
                url: snapshotURL,
                fileName: sourceURL.lastPathComponent,
                fileSize: try fileSize(at: snapshotURL.path),
                md5Checksum: try computeMD5(fileURL: snapshotURL)
            )
        } catch {
            try? FileManager.default.removeItem(at: snapshotURL)
            throw error
        }
    }

    func discardSnapshot(_ snapshot: UploadFileSnapshot) {
        snapshot.discard()
    }

    func uploadFile(
        snapshot: UploadFileSnapshot,
        uploadOperations: [ASCUploadOperation]
    ) async throws -> String {
        do {
            let result = try await uploadFileWithReceipts(
                snapshot: snapshot,
                uploadOperations: uploadOperations,
                maxAttemptsPerPart: 1,
                retryDelayNanoseconds: 0
            )
            return result.fileMD5
        } catch let failure as UploadTransferFailure {
            throw ASCError.network(failure.message)
        }
    }

    func uploadFileWithReceipts(
        snapshot: UploadFileSnapshot,
        uploadOperations: [ASCUploadOperation],
        maxAttemptsPerPart: Int = 3,
        retryDelayNanoseconds: UInt64 = 250_000_000
    ) async throws -> UploadTransferResult {
        let size = snapshot.fileSize
        try Task.checkCancellation()
        let expirationReferenceDate = Date()
        try validateUploadOperations(
            uploadOperations,
            fileSize: size,
            expirationReferenceDate: expirationReferenceDate
        )
        try Task.checkCancellation()

        logger.info("Uploading file: \(snapshot.fileName) (\(size) bytes, \(uploadOperations.count) chunks)")

        var receipts = Array<UploadPartReceipt?>(repeating: nil, count: uploadOperations.count)
        var nextIndex = 0
        while nextIndex < uploadOperations.count {
            let completedBeforeBatch = receipts.compactMap { $0 }
            if Task.isCancelled {
                guard !completedBeforeBatch.isEmpty else {
                    throw CancellationError()
                }
                throw UploadTransferFailure(
                    message: "Upload was cancelled before all parts completed",
                    receipts: completedBeforeBatch
                )
            }

            let batchEnd = min(nextIndex + batchSize, uploadOperations.count)
            let batch = Array(uploadOperations[nextIndex..<batchEnd].enumerated())

            var failures: [(index: Int, message: String)] = []
            var wasCancelled = false
            await withTaskGroup(of: UploadChunkOutcome.self) { group in
                for (batchOffset, operation) in batch {
                    let chunkIndex = nextIndex + batchOffset
                    group.addTask {
                        do {
                            let receipt = try await self.uploadChunk(
                                fileURL: snapshot.url,
                                fileSize: size,
                                operation: operation,
                                chunkIndex: chunkIndex,
                                maxAttempts: max(1, maxAttemptsPerPart),
                                retryDelayNanoseconds: retryDelayNanoseconds
                            )
                            return .success(chunkIndex, receipt)
                        } catch is CancellationError {
                            return .cancelled
                        } catch {
                            return .failure(chunkIndex, Self.transferFailureMessage(from: error))
                        }
                    }
                }
                for await outcome in group {
                    switch outcome {
                    case .success(let index, let receipt):
                        receipts[index] = receipt
                    case .failure(let index, let message):
                        failures.append((index, message))
                    case .cancelled:
                        wasCancelled = true
                        group.cancelAll()
                    }
                }
            }

            let completedReceipts = receipts.compactMap { $0 }
            if let failure = failures.min(by: { $0.index < $1.index }) {
                throw UploadTransferFailure(
                    message: failure.message,
                    receipts: completedReceipts
                )
            }
            if wasCancelled {
                guard !completedReceipts.isEmpty else {
                    throw CancellationError()
                }
                throw UploadTransferFailure(
                    message: "Upload was cancelled before all parts completed",
                    receipts: completedReceipts
                )
            }

            nextIndex = batchEnd
        }

        let completedReceipts = receipts.compactMap { $0 }
        let md5: String
        do {
            md5 = try computeMD5(fileURL: snapshot.url)
        } catch {
            let message = error is CancellationError
                ? "Upload checksum verification was cancelled after byte transfer completed"
                : Self.transferFailureMessage(from: error)
            throw UploadTransferFailure(message: message, receipts: completedReceipts)
        }
        guard md5 == snapshot.md5Checksum else {
            throw UploadTransferFailure(
                message: "The immutable upload snapshot changed during transfer",
                receipts: completedReceipts
            )
        }
        logger.info("Upload complete. MD5: \(md5)")
        return UploadTransferResult(fileMD5: md5, receipts: completedReceipts)
    }

    private func createSnapshot(of fileURL: URL) throws -> URL {
        var snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-mcp-upload-snapshot-\(UUID().uuidString)")
        if !fileURL.pathExtension.isEmpty {
            snapshotURL.appendPathExtension(fileURL.pathExtension)
        }

        let sourceHandle: FileHandle
        do {
            sourceHandle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw ASCError.network("Failed to snapshot upload file '\(fileURL.path)': \(error.localizedDescription)")
        }

        guard FileManager.default.createFile(
            atPath: snapshotURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            try? sourceHandle.close()
            throw ASCError.network("Failed to create an upload snapshot for '\(fileURL.path)'")
        }

        let snapshotHandle: FileHandle
        do {
            snapshotHandle = try FileHandle(forWritingTo: snapshotURL)
        } catch {
            try? sourceHandle.close()
            try? FileManager.default.removeItem(at: snapshotURL)
            throw ASCError.network("Failed to open the upload snapshot: \(error.localizedDescription)")
        }

        do {
            while true {
                if Task.isCancelled {
                    throw CancellationError()
                }
                let data = try sourceHandle.read(upToCount: 1024 * 1024) ?? Data()
                if data.isEmpty { break }
                try snapshotHandle.write(contentsOf: data)
            }
            try snapshotHandle.synchronize()
            try sourceHandle.close()
            try snapshotHandle.close()
            return snapshotURL
        } catch {
            try? sourceHandle.close()
            try? snapshotHandle.close()
            try? FileManager.default.removeItem(at: snapshotURL)
            if error is CancellationError {
                throw CancellationError()
            }
            throw ASCError.network("Failed to snapshot upload file '\(fileURL.path)': \(error.localizedDescription)")
        }
    }

    func validateUploadOperations(
        _ operations: [ASCUploadOperation],
        fileSize: Int,
        expirationReferenceDate: Date
    ) throws {
        guard !operations.isEmpty else {
            throw ASCError.network("Apple returned no upload operations")
        }

        var ranges: [(offset: Int, length: Int, index: Int)] = []
        ranges.reserveCapacity(operations.count)

        for (index, operation) in operations.enumerated() {
            guard let urlString = operation.url,
                  let components = URLComponents(string: urlString),
                  components.scheme?.lowercased() == "https",
                  components.host?.isEmpty == false,
                  components.user == nil,
                  components.password == nil,
                  components.fragment == nil,
                  components.url != nil else {
                throw ASCError.network("Upload operation \(index) has an invalid URL")
            }

            if let expiration = operation.expiration {
                guard let expirationDate = Self.uploadExpirationDate(expiration) else {
                    throw ASCError.network("Upload operation \(index) has an invalid expiration")
                }
                guard expirationDate > expirationReferenceDate else {
                    throw ASCError.network("Upload chunk \(index) URL has expired")
                }
            }
            if let partNumber = operation.partNumber,
               !(1...9_007_199_254_740_991).contains(partNumber) {
                throw ASCError.network("Upload operation \(index) has an invalid part number")
            }

            let offset = operation.offset ?? 0
            let length = operation.length ?? fileSize

            guard offset >= 0 else {
                throw ASCError.network("Upload operation \(index) has negative offset")
            }
            guard length > 0 else {
                throw ASCError.network("Upload operation \(index) has non-positive length")
            }
            guard offset <= fileSize, length <= fileSize - offset else {
                throw ASCError.network("Upload operation \(index) range exceeds file size")
            }

            ranges.append((offset: offset, length: length, index: index))
        }

        var expectedOffset = 0
        for range in ranges.sorted(by: {
            if $0.offset == $1.offset {
                return $0.index < $1.index
            }
            return $0.offset < $1.offset
        }) {
            guard range.offset == expectedOffset else {
                let issue = range.offset < expectedOffset ? "overlaps" : "leaves a gap in"
                throw ASCError.network(
                    "Upload operation \(range.index) \(issue) the file byte coverage"
                )
            }
            expectedOffset = range.offset + range.length
        }

        guard expectedOffset == fileSize else {
            throw ASCError.network("Upload operations do not cover the complete file")
        }
    }

    private func uploadChunk(
        fileURL: URL,
        fileSize: Int,
        operation: ASCUploadOperation,
        chunkIndex: Int,
        maxAttempts: Int,
        retryDelayNanoseconds: UInt64
    ) async throws -> UploadPartReceipt {
        guard let urlString = operation.url,
              let url = URL(string: urlString) else {
            throw ASCError.network("Upload operation \(chunkIndex) has no URL")
        }

        let offset = operation.offset ?? 0
        let length = operation.length ?? fileSize
        try Task.checkCancellation()

        let uploadFileURL: URL
        let discardUploadFile: Bool
        if offset == 0, length == fileSize {
            uploadFileURL = fileURL
            discardUploadFile = false
        } else {
            uploadFileURL = try createChunkFile(
                from: fileURL,
                offset: offset,
                length: length,
                chunkIndex: chunkIndex
            )
            discardUploadFile = true
        }
        defer {
            if discardUploadFile {
                try? FileManager.default.removeItem(at: uploadFileURL)
            }
        }

        let effectiveMethod = operation.method ?? "PUT"
        let allowedAttempts = Self.isExplicitPUT(operation.method) ? max(1, maxAttempts) : 1

        for attempt in 1...allowedAttempts {
            try Task.checkCancellation()

            if let expiration = operation.expiration,
               let expirationDate = Self.uploadExpirationDate(expiration),
               expirationDate <= Date() {
                throw ASCError.network("Upload chunk \(chunkIndex) URL has expired")
            }

            var request = URLRequest(url: url)
            request.httpMethod = effectiveMethod
            request.httpShouldHandleCookies = false

            if let headers = operation.requestHeaders {
                for header in headers {
                    if let name = header.name, let value = header.value {
                        request.setValue(value, forHTTPHeaderField: name)
                    }
                }
            }

            logger.debug("Uploading chunk \(chunkIndex): offset=\(offset), length=\(length), attempt=\(attempt)")

            let response: HTTPURLResponse
            do {
                (_, response) = try await transport.upload(for: request, fromFile: uploadFileURL)
            } catch {
                if error is CancellationError || Task.isCancelled {
                    throw CancellationError()
                }
                guard attempt < allowedAttempts else {
                    let suffix = allowedAttempts == 1 ? "" : " after \(attempt) attempts"
                    throw ASCError.network("Upload chunk \(chunkIndex) transfer failed\(suffix)")
                }
                if retryDelayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds)
                }
                continue
            }

            guard response.url == url else {
                throw ASCError.network("Upload chunk \(chunkIndex) redirect response was rejected")
            }
            if 200...299 ~= response.statusCode {
                return UploadPartReceipt(
                    operationIndex: chunkIndex,
                    method: effectiveMethod,
                    offset: offset,
                    length: length,
                    attempts: attempt,
                    statusCode: response.statusCode,
                    expiration: operation.expiration,
                    partNumber: operation.partNumber,
                    entityTag: operation.entityTag,
                    responseEntityTag: response.value(forHTTPHeaderField: "ETag")
                )
            }

            guard attempt < allowedAttempts,
                  Self.retryableUploadStatusCodes.contains(response.statusCode) else {
                throw ASCError.network("Upload chunk \(chunkIndex) failed with status \(response.statusCode)")
            }

            try Task.checkCancellation()
            if retryDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: retryDelayNanoseconds)
            }
        }

        throw ASCError.network("Upload chunk \(chunkIndex) transfer failed")
    }

    private static let retryableUploadStatusCodes = Set([408, 429, 500, 502, 503, 504])

    private static func isExplicitPUT(_ method: String?) -> Bool {
        method == "PUT"
    }

    private static func transferFailureMessage(from error: Error) -> String {
        if let ascError = error as? ASCError,
           case .network(let message) = ascError {
            return message
        }
        return error.localizedDescription
    }

    private static func uploadExpirationDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private func createChunkFile(
        from fileURL: URL,
        offset: Int,
        length: Int,
        chunkIndex: Int
    ) throws -> URL {
        let sourceHandle: FileHandle
        do {
            sourceHandle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw ASCError.network("Failed to open file '\(fileURL.path)': \(error.localizedDescription)")
        }

        let chunkURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-mcp-upload-chunk-\(UUID().uuidString)")
        guard FileManager.default.createFile(
            atPath: chunkURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            try? sourceHandle.close()
            throw ASCError.network("Failed to create temporary upload chunk \(chunkIndex)")
        }

        let chunkHandle: FileHandle
        do {
            chunkHandle = try FileHandle(forWritingTo: chunkURL)
        } catch {
            try? sourceHandle.close()
            try? FileManager.default.removeItem(at: chunkURL)
            throw ASCError.network("Failed to open temporary upload chunk \(chunkIndex)")
        }

        do {
            try sourceHandle.seek(toOffset: UInt64(offset))
            var remaining = length
            while remaining > 0 {
                if Task.isCancelled {
                    throw CancellationError()
                }

                let readLength = min(remaining, 1024 * 1024)
                guard let data = try sourceHandle.read(upToCount: readLength), !data.isEmpty else {
                    throw ASCError.network(
                        "Failed to read exact upload range offset=\(offset), length=\(length)"
                    )
                }
                try chunkHandle.write(contentsOf: data)
                remaining -= data.count
            }

            try chunkHandle.synchronize()
            try sourceHandle.close()
            try chunkHandle.close()
            return chunkURL
        } catch {
            try? sourceHandle.close()
            try? chunkHandle.close()
            try? FileManager.default.removeItem(at: chunkURL)
            if error is CancellationError {
                throw CancellationError()
            }
            if let ascError = error as? ASCError {
                throw ascError
            }
            throw ASCError.network("Failed to prepare upload chunk \(chunkIndex)")
        }
    }

    /// Computes MD5 hex checksum of data
    /// - Returns: Lowercase hex string (e.g. "d41d8cd98f00b204e9800998ecf8427e")
    public func computeMD5(data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes MD5 hex checksum of a file without loading it fully into memory.
    /// - Parameter fileURL: File URL to hash.
    /// - Returns: Lowercase hex MD5 checksum.
    /// - Throws: ASCError if the file cannot be read, or CancellationError when hashing is cancelled.
    public func computeMD5(fileURL: URL) throws -> String {
        try Task.checkCancellation()

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw ASCError.network("Failed to open file '\(fileURL.path)': \(error.localizedDescription)")
        }

        var hasher = Insecure.MD5()
        do {
            while true {
                try Task.checkCancellation()
                let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
                if data.isEmpty { break }
                hasher.update(data: data)
            }
            try handle.close()
        } catch {
            try? handle.close()
            if error is CancellationError {
                throw CancellationError()
            }
            throw ASCError.network("Failed to hash file: \(error.localizedDescription)")
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns file size for a given path
    /// - Throws: ASCError if file doesn't exist
    public func fileSize(at filePath: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
        guard let size = attributes[.size] as? Int else {
            throw ASCError.network("Cannot determine file size for '\(filePath)'")
        }
        return size
    }

    /// Returns file name from path
    public func fileName(at filePath: String) -> String {
        return URL(fileURLWithPath: filePath).lastPathComponent
    }
}

struct UploadFileSnapshot: Sendable {
    let url: URL
    let fileName: String
    let fileSize: Int
    let md5Checksum: String

    func discard() {
        try? FileManager.default.removeItem(at: url)
    }
}
